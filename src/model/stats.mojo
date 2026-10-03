"""What the user has gained since quitting.

All figures are derived from the profile and the elapsed time, never stored,
so the numbers stay correct after an edit and cannot drift out of sync with
the quit date.
"""

from lib.text import format_int

# CDC figures: reaching 20 minutes means heart rate and blood pressure have
# dropped back to normal, and it takes roughly 11 minutes for the body to
# clear one cigarette's worth of nicotine.
comptime SECONDS_PER_MINUTE: Int64 = Int64(60)
comptime SECONDS_PER_HOUR: Int64 = Int64(3600)
comptime SECONDS_PER_DAY: Int64 = Int64(86400)
comptime MINUTES_PER_CIGARETTE: Float64 = Float64(11.0)


struct Gains(ImplicitlyCopyable):
    var elapsed_seconds: Int64
    var money: Float64
    var cigarettes: Float64
    var life_minutes: Float64
    var days: Int64

    def __init__(out self):
        self.elapsed_seconds = Int64(0)
        self.money = Float64(0.0)
        self.cigarettes = Float64(0.0)
        self.life_minutes = Float64(0.0)
        self.days = Int64(0)

    def whole_life_minutes(self) -> Int64:
        return Int64(self.life_minutes)

    def whole_cigarettes(self) -> Int64:
        return Int64(self.cigarettes)


def elapsed_since(quit_epoch: Int64, now_epoch: Int64) -> Int64:
    """Seconds smoke free, never negative.

    A quit date in the future means the countdown has not started, which is the
    normal state right after onboarding.
    """
    var delta = now_epoch - quit_epoch
    if delta < Int64(0):
        return Int64(0)
    return delta


def cost_per_cigarette(pack_price: Float64, pack_size: Int64) -> Float64:
    """Price of one cigarette, guarding against a zero or negative pack size."""
    if pack_size <= Int64(0):
        return Float64(0.0)
    if pack_price < Float64(0.0):
        return Float64(0.0)
    return pack_price / Float64(pack_size)


def daily_cost(cigs_per_day: Int64, pack_price: Float64, pack_size: Int64) -> Float64:
    return Float64(cigs_per_day) * cost_per_cigarette(pack_price, pack_size)


def compute(
    cigs_per_day: Int64,
    pack_price: Float64,
    pack_size: Int64,
    quit_epoch: Int64,
    now_epoch: Int64,
) -> Gains:
    """Everything the dashboard shows, from the profile and the clock."""
    var out = Gains()
    var elapsed = elapsed_since(quit_epoch, now_epoch)
    out.elapsed_seconds = elapsed
    out.days = elapsed // SECONDS_PER_DAY
    var day_fraction = Float64(elapsed) / Float64(SECONDS_PER_DAY)
    out.cigarettes = Float64(cigs_per_day) * day_fraction
    out.money = daily_cost(cigs_per_day, pack_price, pack_size) * day_fraction
    out.life_minutes = out.cigarettes * MINUTES_PER_CIGARETTE
    return out


def cigarettes_avoided(gains: Gains) -> Int64:
    return gains.whole_cigarettes()


def life_recovered_minutes(gains: Gains) -> Int64:
    return gains.whole_life_minutes()


def hours_smoke_free(gains: Gains) -> Int64:
    return gains.elapsed_seconds // SECONDS_PER_HOUR


def money_per_day(
    cigs_per_day: Int64, pack_price: Float64, pack_size: Int64
) -> Float64:
    return daily_cost(cigs_per_day, pack_price, pack_size)


def seconds_text(gains: Gains) -> String:
    """Plain debug helper: the elapsed time as '1d 2h 3m'."""
    var days = gains.elapsed_seconds // SECONDS_PER_DAY
    var hours = (gains.elapsed_seconds % SECONDS_PER_DAY) // SECONDS_PER_HOUR
    var minutes = (gains.elapsed_seconds % SECONDS_PER_HOUR) // SECONDS_PER_MINUTE
    return format_int(days) + "d " + format_int(hours) + "h " + format_int(minutes) + "m"
