-- Comms/RateLimit.lua
-- PURE: no WoW globals. A token bucket for outgoing messages and the retry back-off.
-- The real limits are unknown (docs/PROTOCOL.md); these defaults are deliberately gentle.

local _, ns = ...

local RateLimit = {}
ns.RateLimit = RateLimit

RateLimit.RATE = 2        -- messages per second, sustained
RateLimit.BURST = 4       -- messages that may go out at once
RateLimit.MAX_ATTEMPTS = 6

function RateLimit.New(rate, burst, now)
    return { rate = rate or RateLimit.RATE, burst = burst or RateLimit.BURST, tokens = burst or RateLimit.BURST, at = now }
end

function RateLimit.Take(b, now)
    local elapsed = math.max(0, now - (b.at or now))
    b.tokens = math.min(b.burst, b.tokens + elapsed * b.rate)
    b.at = now
    if b.tokens >= 1 then
        b.tokens = b.tokens - 1
        return true
    end
    return false
end

-- Seconds to wait before retry number `attempt` (1, 2, 3, ...): 2, 4, 8, ... capped at 60.
function RateLimit.Backoff(attempt)
    return math.min(60, 2 ^ math.max(1, attempt))
end
