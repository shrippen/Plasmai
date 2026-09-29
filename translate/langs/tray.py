# -*- coding: utf-8 -*-
"""Tray client (ROADMAP pillar 7) strings: the tray icon's menu. Merged by
fill_po.py after the per-language dictionaries (entries there win).

Column order: de, fr, es, it, nl, pt_BR, pl, uk, ru, ja, zh_CN
"""

LANGS = ["de", "fr", "es", "it", "nl", "pt_BR", "pl", "uk", "ru", "ja", "zh_CN"]

ROWS = [
    ("Open Plasmai",
     "Plasmai öffnen", "Ouvrir Plasmai", "Abrir Plasmai", "Apri Plasmai", "Plasmai openen", "Abrir o Plasmai",
     "Otwórz Plasmai", "Відкрити Plasmai", "Открыть Plasmai", "Plasmai を開く", "打开 Plasmai"),
    ("Stop %1 · %2",
     "%1 · %2 stoppen", "Arrêter %1 · %2", "Detener %1 · %2", "Ferma %1 · %2", "%1 · %2 stoppen",
     "Parar %1 · %2", "Zatrzymaj %1 · %2", "Зупинити %1 · %2", "Остановить %1 · %2", "%1 · %2 を停止",
     "停止 %1 · %2"),
    ("Start %1 · %2",
     "%1 · %2 starten", "Démarrer %1 · %2", "Iniciar %1 · %2", "Avvia %1 · %2", "%1 · %2 starten",
     "Iniciar %1 · %2", "Uruchom %1 · %2", "Запустити %1 · %2", "Запустить %1 · %2", "%1 · %2 を開始",
     "开始 %1 · %2"),
    ("Start at login",
     "Bei der Anmeldung starten", "Lancer à l’ouverture de session", "Iniciar al iniciar sesión",
     "Avvia all’accesso", "Starten bij aanmelden", "Iniciar ao entrar", "Uruchamiaj po zalogowaniu",
     "Запускати під час входу", "Запускать при входе в систему", "ログイン時に起動", "登录时启动"),
    ("Quit",
     "Beenden", "Quitter", "Salir", "Esci", "Afsluiten", "Sair", "Zakończ", "Вийти", "Выйти", "終了", "退出"),
]

T_BY_LANG = {lang: {} for lang in LANGS}
for row in ROWS:
    for lang, value in zip(LANGS, row[1:]):
        T_BY_LANG[lang][row[0]] = value
