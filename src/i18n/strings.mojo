# Copyright (C) 2026 Luís Louro
#
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Licensed under the GNU General Public License, version 3 or later. The full
# text is in LICENSE.

"""Portuguese and English strings, plus locale-aware number formatting.

Every user-visible string in the app lives here. `lookup` returns the key
itself for an unknown key, which makes a missing translation obvious in the
interface and lets the test suite assert that both languages are complete.

Number formatting differs between the two languages: Portuguese writes
1.234,50 and English writes 1,234.50, and English counts zero as plural while
Portuguese does not.
"""

from lib.text import english_plural, format_fixed, format_int, group_with, split_at_dot


comptime LANG_PT: Int = 0
comptime LANG_EN: Int = 1
comptime LANG_COUNT: Int = 2


struct Translations(ImplicitlyCopyable):
    var lang: Int

    def __init__(out self, lang: Int = LANG_PT):
        self.lang = lang

    def is_portuguese(self) -> Bool:
        return self.lang == LANG_PT

    def toggle(self) -> Translations:
        return Translations(LANG_EN if self.lang == LANG_PT else LANG_PT)

    def code(self) -> String:
        if self.lang == LANG_PT:
            return String("pt_PT")
        return String("en")

    def t(self, key: String) -> String:
        return lookup(self.lang, key)

    # ---- locale aware formatting ---------------------------------------

    def decimal_separator(self) -> String:
        return String(",") if self.lang == LANG_PT else String(".")

    def group_separator(self) -> String:
        return String(".") if self.lang == LANG_PT else String(",")

    def amount(self, value: Float64) -> String:
        """Money-style number with grouped thousands and two decimals."""
        var parts = split_at_dot(format_fixed(value, 2))
        return group_with(parts[0], self.group_separator()) + self.decimal_separator() + parts[
            1
        ]

    def integer(self, value: Int64) -> String:
        return group_with(format_int(value), self.group_separator())

    def plural(self, count: Int64, singular_key: String, plural_key: String) -> String:
        """Pick the singular or plural form for the current language."""
        if self.lang == LANG_PT:
            if count == Int64(1):
                return self.t(singular_key)
            return self.t(plural_key)
        if english_plural(count):
            return self.t(plural_key)
        return self.t(singular_key)

    def minutes(self, count: Int64) -> String:
        return self.integer(count) + " " + self.plural(count, "unit_minute", "unit_minutes")

    def cigarettes(self, count: Int64) -> String:
        return self.integer(count) + " " + self.plural(
            count, "unit_cigarette", "unit_cigarettes"
        )

    def days(self, count: Int64) -> String:
        return self.integer(count) + " " + self.plural(count, "unit_day", "unit_days")

    def months(self, count: Int64) -> String:
        return self.integer(count) + " " + self.plural(count, "unit_month", "unit_months")

    def years(self, count: Int64) -> String:
        return self.integer(count) + " " + self.plural(count, "unit_year", "unit_years")


def language_from_code(code: String) -> Int:
    """Map a stored language code back to a language id."""
    if code == "en" or code == "en_GB" or code == "en_US":
        return LANG_EN
    return LANG_PT


def lookup(lang: Int, key: String) -> String:
    """Translation for `key`, or the key itself when it is unknown."""
    var pt = lang == LANG_PT

    # Application
    if key == "app_name":
        return String("smokenot")
    if key == "app_tagline":
        return String("Cada minuto sem fumar conta.") if pt else String("Every minute without a smoke counts.")
    if key == "nav_dashboard":
        return String("Painel") if pt else String("Dashboard")
    if key == "nav_milestones":
        return String("Marcos") if pt else String("Milestones")
    if key == "nav_journal":
        return String("Diário") if pt else String("Journal")
    if key == "nav_settings":
        return String("Definições") if pt else String("Settings")
    if key == "nav_quit":
        return String("Abandonar") if pt else String("Quit smoking")
    if key == "common_ok":
        return String("OK") if pt else String("OK")
    if key == "common_cancel":
        return String("Cancelar") if pt else String("Cancel")
    if key == "common_save":
        return String("Guardar") if pt else String("Save")
    if key == "common_close":
        return String("Fechar") if pt else String("Close")
    if key == "common_back":
        return String("Voltar") if pt else String("Back")
    if key == "common_next":
        return String("Seguinte") if pt else String("Next")
    if key == "common_yes":
        return String("Sim") if pt else String("Yes")
    if key == "common_no":
        return String("Não") if pt else String("No")

    # The setup fields
    if key == "field_cigs_per_day":
        return String("Cigarros por dia") if pt else String("Cigarettes per day")
    if key == "field_pack_size":
        return String("Cigarros por pacote") if pt else String("Cigarettes per pack")
    if key == "field_pack_price":
        return String("Preço do pacote") if pt else String("Price per pack")
    if key == "field_quit_date":
        return String("Dia em que vais parar") if pt else String("The day you stop smoking")
    if key == "field_years":
        return String("Anos") if pt else String("Years")
    if key == "field_months":
        return String("Meses") if pt else String("Months")
    if key == "field_days_ago":
        return String("dias atrás") if pt else String("days ago")
    if key == "date_in_days":
        return String("em ") if pt else String("in ")
    if key == "field_now":
        return String("Agora") if pt else String("Right now")
    if key == "field_tomorrow":
        return String("Amanhã") if pt else String("Tomorrow")
    if key == "field_yesterday":
        return String("Ontem") if pt else String("Yesterday")
    if key == "error_positive":
        return String("Escreve um número maior que zero.") if pt else String("Enter a number greater than zero.")
    if key == "error_invalid":
        return String("Isso não parece um número válido.") if pt else String("That does not look like a valid number.")

    # Dashboard
    if key == "dash_title":
        return String("O que já ganhaste") if pt else String("What you have gained")
    if key == "dash_money":
        return String("Dinheiro guardado") if pt else String("Money saved")
    if key == "dash_cigs":
        return String("Cigarros evitados") if pt else String("Cigarettes not smoked")
    if key == "dash_life":
        return String("Tempo de vida recuperado") if pt else String("Life regained")
    if key == "dash_since":
        return String("Sem fumar desde") if pt else String("Smoke free since")
    if key == "dash_starts_in":
        return String("Começa em ") if pt else String("Starts in ")
    if key == "dash_starts_on":
        return String("Começa em ") if pt else String("Starts on ")
    if key == "dash_starts_today":
        return String("Hoje é o dia.") if pt else String("Today is the day.")
    if key == "dash_next_milestone":
        return String("Próximo marco") if pt else String("Next milestone")
    if key == "dash_streak":
        return String("Dias sem fumar") if pt else String("Days smoke free")
    if key == "dash_per_day":
        return String("Por dia") if pt else String("Per day")
    if key == "dash_quit_now":
        return String("Parar agora!") if pt else String("Quit now!")
    if key == "dash_encouragement":
        return String("Cada cigarro evitado é um minuto de vida.") if pt else String("Every cigarette avoided is a minute of life.")

    # Milestones
    if key == "milestones_title":
        return String("A tua recuperação") if pt else String("Your recovery")
    if key == "milestones_reached":
        return String("Alcançado") if pt else String("Reached")
    if key == "milestones_pending":
        return String("Falta") if pt else String("To go")
    if key == "milestone_20min":
        return String("A pressão arterial e o pulso normalizam-se.") if pt else String("Blood pressure and pulse normalise.")
    if key == "milestone_8h":
        return String("O oxigénio no sangue sobe e o monóxido de carbono desce.") if pt else String("Blood oxygen rises and carbon monoxide drops.")
    if key == "milestone_24h":
        return String("Reduz o risco de ataque cardíaco.") if pt else String("Heart attack risk starts to fall.")
    if key == "milestone_48h":
        return String("O olfato e o gosto melhoram.") if pt else String("Smell and taste begin to recover.")
    if key == "milestone_72h":
        return String("Os pulmões relaxam e os bronquios começam a recuperar.") if pt else String("Lungs relax and bronchial tubes begin to recover.")
    if key == "milestone_1w":
        return String("Dorme-se melhor e há mais energia.") if pt else String("Sleep improves and energy rises.")
    if key == "milestone_2w":
        return String("A circulação melhora.") if pt else String("Circulation improves.")
    if key == "milestone_1m":
        return String("As rugas da pele começam a suavizar.") if pt else String("Skin texture starts to even out.")
    if key == "milestone_3m":
        return String("A função pulmonar sobe até 30%.") if pt else String("Lung function can rise by up to 30%.")
    if key == "milestone_9m":
        return String("Os pulmões estão significativamente mais saudáveis.") if pt else String("Lungs are noticeably healthier.")
    if key == "milestone_1y":
        return String("O risco de doença coronária cai pela metade.") if pt else String("Coronary heart disease risk is cut in half.")
    if key == "milestone_5y":
        return String("O risco de AVC iguala o de quem nunca fumou.") if pt else String("Stroke risk matches a non-smoker's.")
    if key == "milestone_10y":
        return String("O risco de cancro de pulmão cai pela metade.") if pt else String("Lung cancer risk is roughly halved.")
    if key == "milestone_15y":
        return String("O risco de doença coronária iguala o de não fumadores.") if pt else String("Coronary heart disease risk matches a non-smoker's.")
    if key == "milestones_disclaimer":
        return (
            String("Estes números vêm de estudos publicados e são aproximações, não aconselhamento médico.")
            if pt
            else String("These figures come from published studies. They are approximations, not medical advice.")
        )

    # Craving
    if key == "craving_title":
        return String("A vontade vai passar") if pt else String("This craving will pass")
    if key == "craving_body":
        return String("Respira comigo durante cinco minutos.") if pt else String("Breathe with me for five minutes.")
    if key == "craving_start":
        return String("Começar") if pt else String("Start")
    if key == "craving_stop":
        return String("Parar") if pt else String("Stop")
    if key == "craving_inhale":
        return String("Inspira") if pt else String("Breathe in")
    if key == "craving_exhale":
        return String("Expira") if pt else String("Breathe out")
    if key == "craving_hold":
        return String("Segura") if pt else String("Hold")
    if key == "craving_seconds":
        return String("segundos") if pt else String("seconds")
    if key == "craving_done_title":
        return String("Passou. Conseguiste.") if pt else String("It passed. You did it.")
    if key == "craving_done_body":
        return String("A vontade mais forte dura entre três e cinco minutos.") if pt else String("The strongest urge lasts three to five minutes.")
    if key == "craving_log":
        return String("Registar este momento") if pt else String("Log this moment")
    if key == "craving_water":
        return String("Bebe um pouco de água.") if pt else String("Have a sip of water.")
    if key == "craving_move":
        return String("Levanta-te e muda de sítio.") if pt else String("Stand up and move somewhere else.")
    if key == "craving_breathe_hint":
        return String("Quatro segundos a inspirar, seis a soltar.") if pt else String("Four seconds in, six seconds out.")

    # Journal
    if key == "journal_title":
        return String("Diário") if pt else String("Journal")
    if key == "journal_add":
        return String("Nova entrada") if pt else String("New entry")
    if key == "journal_craving":
        return String("Vontade") if pt else String("Craving")
    if key == "journal_slip":
        return String("Recaída") if pt else String("Slip")
    if key == "journal_note":
        return String("Nota") if pt else String("Note")
    if key == "journal_note_hint":
        return String("O que sentiste?") if pt else String("What did you feel?")
    if key == "journal_empty":
        return String("Ainda não há entradas.") if pt else String("No entries yet.")
    if key == "journal_saved":
        return String("Entrada guardada.") if pt else String("Entry saved.")
    if key == "journal_count":
        return String("entradas") if pt else String("entries")

    # Settings
    if key == "settings_title":
        return String("Definições") if pt else String("Settings")
    if key == "settings_intro":
        return (
            String("Preenche isto uma vez. O painel mostra os teus progressos a partir daqui.")
            if pt
            else String("Fill this in once. The dashboard counts from here.")
        )
    if key == "settings_language":
        return String("Idioma") if pt else String("Language")
    if key == "settings_save":
        return String("Começar a contar") if pt else String("Start counting")
    if key == "settings_edit_profile":
        return String("Editar perfil") if pt else String("Edit profile")
    if key == "settings_reset":
        return String("Apagar tudo") if pt else String("Delete all data")
    if key == "settings_reset_confirm":
        return String("Isto apaga o teu progresso. Tens a certeza?") if pt else String("This deletes your progress. Are you sure?")
    if key == "settings_data_path":
        return String("Ficheiro de dados") if pt else String("Data file")
    if key == "settings_about":
        return String("Acerca") if pt else String("About")
    if key == "settings_about_body":
        return (
            String("smokenot funciona completamente offline. Nenhum dado sai deste computador.")
            if pt
            else String("smokenot works entirely offline. No data leaves this computer.")
        )
    if key == "settings_health_source":
        return String("Dados de saúde: Centers for Disease Control and Prevention.") if pt else String("Health data: Centers for Disease Control and Prevention.")

    # The about box. The version, the address and the copyright notice are not
    # here: they are the same in both languages, so they are written once in
    # `ui.screens` next to the box itself.
    if key == "about_title":
        return String("Acerca do smokenot") if pt else String("About smokenot")
    if key == "about_version":
        return String("Versão") if pt else String("Version")
    if key == "about_website":
        return String("Sítio") if pt else String("Website")
    if key == "about_license":
        return (
            String("Licenciado sob a Licença Pública Geral GNU, versão 3 ou posterior. O texto completo está no ficheiro LICENSE, e em gnu.org/licenses.")
            if pt
            else String("Licensed under the GNU General Public License, version 3 or later. The full text is in the LICENSE file, and at gnu.org/licenses.")
        )

    # Units
    if key == "unit_minute":
        return String("minuto") if pt else String("minute")
    if key == "unit_minutes":
        return String("minutos") if pt else String("minutes")
    if key == "unit_hour":
        return String("hora") if pt else String("hour")
    if key == "unit_hours":
        return String("horas") if pt else String("hours")
    if key == "unit_day":
        return String("dia") if pt else String("day")
    if key == "unit_days":
        return String("dias") if pt else String("days")
    if key == "unit_month":
        return String("mês") if pt else String("month")
    if key == "unit_months":
        return String("meses") if pt else String("months")
    if key == "unit_year":
        return String("ano") if pt else String("year")
    if key == "unit_years":
        return String("anos") if pt else String("years")
    if key == "unit_cigarette":
        return String("cigarro") if pt else String("cigarette")
    if key == "unit_cigarettes":
        return String("cigarros") if pt else String("cigarettes")

    return key
