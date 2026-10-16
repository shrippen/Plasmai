#pragma once

#include <QString>

/** True when the command line asks for the terminal client (--tui). */
bool wantsTui(int argc, char *argv[]);

/** Runs the terminal client until it quits; returns the exit code. */
int runTui(int argc, char *argv[], const QString &version);
