# -*- coding: utf-8 -*-
"""Translations for the terminal client (plasmai-app --tui) and the statistics day switcher
(2.6.0). Merged with the per-language dictionaries by fill_po.py. The key letters in the key
lines (s, t, w, r, q) are the keys themselves and stay as they are.

Column order: en, de, fr, es, it, nl, pt_BR, pl, uk, ru, ja, zh_CN
"""

LANGS = ["en", "de", "fr", "es", "it", "nl", "pt_BR", "pl", "uk", "ru", "ja", "zh_CN"]

ROWS = [
    ("Nothing is running",
     "Es läuft nichts", "Rien n’est en cours", "No hay nada en marcha", "Niente in corso", "Er loopt niets", "Nada em andamento", "Nic nie jest uruchomione", "Нічого не запущено", "Ничего не запущено", "実行中のものはありません", "没有正在运行的计时"),
    ("Week",
     "Woche", "Semaine", "Semana", "Settimana", "Week", "Semana", "Tydzień", "Тиждень", "Неделя", "週", "本周"),
    ("No recent entries",
     "Keine letzten Einträge", "Aucune entrée récente", "No hay entradas recientes", "Nessuna voce recente", "Geen recente items", "Nenhuma entrada recente", "Brak ostatnich wpisów", "Немає останніх записів", "Нет последних записей", "最近のエントリはありません", "没有最近的条目"),
    ("No entries this week",
     "Keine Einträge in dieser Woche", "Aucune entrée cette semaine", "No hay entradas esta semana", "Nessuna voce questa settimana", "Geen items deze week", "Nenhuma entrada nesta semana", "Brak wpisów w tym tygodniu", "Цього тижня записів немає", "На этой неделе записей нет", "今週のエントリはありません", "本周没有条目"),
    ("No gaps in the work day",
     "Keine Lücken im Arbeitstag", "Aucun trou dans la journée de travail", "No hay huecos en la jornada", "Nessun vuoto nella giornata lavorativa", "Geen gaten in de werkdag", "Nenhuma lacuna no dia de trabalho", "Brak luk w dniu pracy", "Немає прогалин у робочому дні", "Нет пробелов в рабочем дне", "勤務時間内に空きはありません", "工作日内没有空档"),
    ("Gaps:",
     "Lücken:", "Trous :", "Huecos:", "Vuoti:", "Gaten:", "Lacunas:", "Luki:", "Прогалини:", "Пробелы:", "空き:", "空档:"),
    ("Total",
     "Summe", "Total", "Total", "Totale", "Totaal", "Total", "Suma", "Разом", "Итого", "合計", "合计"),
    ("1–9 start · s stop · t day · w week · r refresh · q quit",
     "1–9 starten · s stoppen · t Tag · w Woche · r aktualisieren · q beenden",
     "1–9 démarrer · s arrêter · t jour · w semaine · r actualiser · q quitter",
     "1–9 iniciar · s detener · t día · w semana · r actualizar · q salir",
     "1–9 avvia · s ferma · t giorno · w settimana · r aggiorna · q esci",
     "1–9 starten · s stoppen · t dag · w week · r vernieuwen · q afsluiten",
     "1–9 iniciar · s parar · t dia · w semana · r atualizar · q sair",
     "1–9 start · s stop · t dzień · w tydzień · r odśwież · q zakończ",
     "1–9 запуск · s стоп · t день · w тиждень · r оновити · q вихід",
     "1–9 запуск · s стоп · t день · w неделя · r обновить · q выход",
     "1–9 開始 · s 停止 · t 日 · w 週 · r 更新 · q 終了",
     "1–9 开始 · s 停止 · t 日 · w 周 · r 刷新 · q 退出"),
    ("Esc back · s stop · r refresh · q quit",
     "Esc zurück · s stoppen · r aktualisieren · q beenden",
     "Esc retour · s arrêter · r actualiser · q quitter",
     "Esc volver · s detener · r actualizar · q salir",
     "Esc indietro · s ferma · r aggiorna · q esci",
     "Esc terug · s stoppen · r vernieuwen · q afsluiten",
     "Esc voltar · s parar · r atualizar · q sair",
     "Esc wstecz · s stop · r odśwież · q zakończ",
     "Esc назад · s стоп · r оновити · q вихід",
     "Esc назад · s стоп · r обновить · q выход",
     "Esc 戻る · s 停止 · r 更新 · q 終了",
     "Esc 返回 · s 停止 · r 刷新 · q 退出"),
    ("Set up a connection in the Plasmai app first",
     "Richte zuerst in der Plasmai-App eine Verbindung ein", "Configurez d’abord une connexion dans l’application Plasmai", "Configura primero una conexión en la app Plasmai", "Configura prima una connessione nell’app Plasmai", "Stel eerst een verbinding in in de Plasmai-app", "Configure primeiro uma conexão no app Plasmai", "Najpierw skonfiguruj połączenie w aplikacji Plasmai", "Спершу налаштуйте з’єднання в застосунку Plasmai", "Сначала настройте подключение в приложении Plasmai", "先に Plasmai アプリで接続を設定してください", "请先在 Plasmai 应用中设置连接"),
    ("Server not reachable",
     "Server nicht erreichbar", "Serveur injoignable", "Servidor no disponible", "Server non raggiungibile", "Server niet bereikbaar", "Servidor inacessível", "Serwer nieosiągalny", "Сервер недоступний", "Сервер недоступен", "サーバーに接続できません", "无法连接服务器"),
    ("Offline · %1 not synced",
     "Offline · %1 nicht synchronisiert", "Hors ligne · %1 non synchronisé(s)", "Sin conexión · %1 sin sincronizar", "Offline · %1 non sincronizzati", "Offline · %1 niet gesynchroniseerd", "Offline · %1 não sincronizado(s)", "Offline · niezsynchronizowane: %1", "Офлайн · не синхронізовано: %1", "Офлайн · не синхронизировано: %1", "オフライン · 未同期 %1 件", "离线 · %1 项未同步"),
    ("Online",
     "Online", "En ligne", "En línea", "Online", "Online", "Online", "Online", "Онлайн", "Онлайн", "オンライン", "在线"),
    ("Could not refresh",
     "Aktualisieren fehlgeschlagen", "Échec de l’actualisation", "No se pudo actualizar", "Impossibile aggiornare", "Vernieuwen mislukt", "Não foi possível atualizar", "Nie udało się odświeżyć", "Не вдалося оновити", "Не удалось обновить", "更新できませんでした", "无法刷新"),
    ("This build has no demo",
     "Dieser Build hat keine Demo", "Cette version n’a pas de démo", "Esta compilación no tiene demo", "Questa build non ha la demo", "Deze build heeft geen demo", "Esta compilação não tem demo", "Ta kompilacja nie ma wersji demo", "У цій збірці немає демо", "В этой сборке нет демо", "このビルドにはデモがありません", "此版本没有演示"),
    ("No activities this day",
     "Keine Tätigkeiten an diesem Tag", "Aucune activité ce jour-là", "No hay actividades este día", "Nessuna attività in questo giorno", "Geen activiteiten op deze dag", "Nenhuma atividade neste dia", "Brak czynności tego dnia", "Цього дня немає дій", "В этот день нет действий", "この日のアクティビティはありません", "这一天没有活动"),
]

T_BY_LANG = {lang: {} for lang in LANGS}
for row in ROWS:
    msgid, values = row[0], (row[0],) + row[1:]
    assert len(values) == len(LANGS), msgid
    for lang, value in zip(LANGS, values):
        T_BY_LANG[lang][msgid] = value
