from i18n.strings import (
    LANG_COUNT,
    LANG_EN,
    LANG_PT,
    Translations,
    language_from_code,
    lookup,
)
from lib.text import split_on
from tests.harness import Harness, begin_suite, check, check_eq, check_int

# Every user-visible key. A key missing from either language would show up in
# the interface as its own name, so the suite checks all of them.
comptime KEY_LIST = "app_name app_tagline nav_dashboard nav_milestones nav_journal nav_settings nav_quit common_ok common_cancel common_save common_close common_back common_next common_yes common_no field_cigs_per_day field_pack_size field_pack_price field_quit_date field_years field_months field_days_ago date_in_days field_now field_tomorrow field_yesterday error_positive error_invalid dash_title dash_money dash_cigs dash_life dash_since dash_starts_in dash_starts_on dash_starts_today dash_quit_now dash_next_milestone dash_streak dash_per_day dash_encouragement milestones_title milestones_reached milestones_pending milestone_20min milestone_8h milestone_24h milestone_48h milestone_72h milestone_1w milestone_2w milestone_1m milestone_3m milestone_9m milestone_1y milestone_5y milestone_10y milestone_15y milestones_disclaimer craving_title craving_body craving_start craving_stop craving_inhale craving_exhale craving_hold craving_seconds craving_done_title craving_done_body craving_log craving_water craving_move craving_breathe_hint journal_title journal_add journal_craving journal_slip journal_note journal_note_hint journal_empty journal_saved journal_count settings_title settings_intro settings_language settings_save settings_edit_profile settings_reset settings_reset_confirm settings_data_path settings_about settings_about_body settings_health_source unit_minute unit_minutes unit_hour unit_hours unit_day unit_days unit_month unit_months unit_year unit_years unit_cigarette unit_cigarettes"


def run(mut h: Harness):
    begin_suite(h, "i18n.strings")

    # ---- completeness --------------------------------------------------

    var lang = LANG_PT
    while lang < LANG_COUNT:
        var keys = split_on(KEY_LIST, " ")
        var missing = 0
        for key in keys:
            var text = lookup(lang, key)
            if text == key or text.byte_length() == 0:
                missing += 1
                print("   missing in", lang, ":", key)
        check_int(h, Int64(missing), Int64(0), "every key is translated")
        check(h, len(keys) > 90, "key list is not truncated")
        lang += 1

    # ---- known translations -------------------------------------------

    var pt = Translations(LANG_PT)
    var en = Translations(LANG_EN)
    check_eq(h, pt.t("nav_dashboard"), "Painel", "pt dashboard")
    check_eq(h, en.t("nav_dashboard"), "Dashboard", "en dashboard")
    check_eq(h, pt.t("nav_settings"), "Definições", "pt settings")
    check_eq(h, en.t("nav_settings"), "Settings", "en settings")
    check_eq(h, pt.t("journal_slip"), "Recaída", "pt slip")
    check_eq(h, en.t("journal_slip"), "Slip", "en slip")
    check_eq(h, pt.t("app_name"), "smokenot", "app name is not translated")
    check_eq(h, en.t("app_name"), "smokenot", "app name is the same in english")
    check_eq(h, pt.t("dash_quit_now"), "Parar agora!", "pt quit now")
    check_eq(h, en.t("dash_quit_now"), "Quit now!", "en quit now")

    check_eq(h, pt.t("no_such_key"), "no_such_key", "unknown key falls back")
    check_eq(h, en.t("no_such_key"), "no_such_key", "unknown key falls back in english")

    # ---- language switching -------------------------------------------

    check(h, pt.is_portuguese(), "pt reports itself")
    check(h, not en.is_portuguese(), "en does not")
    check_eq(h, pt.toggle().code(), "en", "toggle switches to english")
    check_eq(h, en.toggle().code(), "pt_PT", "toggle switches back")
    check(h, pt.toggle().toggle().is_portuguese(), "toggle twice returns to portuguese")
    check_int(h, Int64(language_from_code("en")), Int64(LANG_EN), "code to english")
    check_int(h, Int64(language_from_code("pt_PT")), Int64(LANG_PT), "code to portuguese")
    check_int(h, Int64(language_from_code("nonsense")), Int64(LANG_PT), "unknown code")
    check_int(h, Int64(language_from_code("")), Int64(LANG_PT), "empty code")

    # ---- number formatting --------------------------------------------

    check_eq(h, en.amount(Float64(1234.5)), "1,234.50", "en amount")
    check_eq(h, pt.amount(Float64(1234.5)), "1.234,50", "pt amount")
    check_eq(h, en.amount(Float64(0.0)), "0.00", "en zero")
    check_eq(h, pt.amount(Float64(0.0)), "0,00", "pt zero")
    check_eq(h, en.amount(Float64(999.99)), "999.99", "en small amount")
    check_eq(h, en.amount(Float64(-1234.5)), "-1,234.50", "en negative amount")
    check_eq(h, pt.amount(Float64(-1234.5)), "-1.234,50", "pt negative amount")
    check_eq(h, en.amount(Float64(1000000.0)), "1,000,000.00", "en millions")
    check_eq(h, en.integer(Int64(1234567)), "1,234,567", "en grouped integer")
    check_eq(h, pt.integer(Int64(1234567)), "1.234.567", "pt grouped integer")
    check_eq(h, en.integer(Int64(100)), "100", "en short integer")
    check_eq(h, pt.integer(Int64(-4200)), "-4.200", "pt negative integer")

    # ---- plurals -------------------------------------------------------

    check_eq(h, en.plural(Int64(1), "unit_minute", "unit_minutes"), "minute", "en one")
    check_eq(h, en.plural(Int64(0), "unit_minute", "unit_minutes"), "minutes", "en zero")
    check_eq(h, en.plural(Int64(5), "unit_minute", "unit_minutes"), "minutes", "en many")
    check_eq(h, pt.plural(Int64(1), "unit_minute", "unit_minutes"), "minuto", "pt one")
    check_eq(h, pt.plural(Int64(0), "unit_minute", "unit_minutes"), "minutos", "pt zero")
    check_eq(h, pt.plural(Int64(5), "unit_minute", "unit_minutes"), "minutos", "pt many")

    check_eq(h, en.minutes(Int64(1)), "1 minute", "en one minute")
    check_eq(h, en.minutes(Int64(0)), "0 minutes", "en zero minutes")
    check_eq(h, en.minutes(Int64(1234)), "1,234 minutes", "en many minutes")
    check_eq(h, pt.minutes(Int64(1)), "1 minuto", "pt one minute")
    check_eq(h, pt.minutes(Int64(1234)), "1.234 minutos", "pt many minutes")
    check_eq(h, en.cigarettes(Int64(1)), "1 cigarette", "en one cigarette")
    check_eq(h, en.cigarettes(Int64(0)), "0 cigarettes", "en zero cigarettes")
    check_eq(h, pt.cigarettes(Int64(2)), "2 cigarros", "pt many cigarettes")
    check_eq(h, en.days(Int64(1)), "1 day", "en one day")
    check_eq(h, pt.days(Int64(30)), "30 dias", "pt many days")

    # Months and years read the same way as the other units.
    check_eq(h, en.months(Int64(1)), "1 month", "en one month")
    check_eq(h, en.months(Int64(2)), "2 months", "en two months")
    check_eq(h, pt.months(Int64(1)), "1 mês", "pt one month")
    check_eq(h, pt.months(Int64(5)), "5 meses", "pt many months")
    check_eq(h, en.years(Int64(1)), "1 year", "en one year")
    check_eq(h, pt.years(Int64(1)), "1 ano", "pt one year")
    check_eq(h, pt.years(Int64(5)), "5 anos", "pt many years")
