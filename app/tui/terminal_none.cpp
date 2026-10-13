#include "terminal.h"

Terminal::Terminal(QObject *parent)
    : QObject(parent)
{
}

Terminal::~Terminal() = default;

bool Terminal::isSupported()
{
    return false;
}

bool Terminal::open()
{
    return false;
}

void Terminal::close()
{
}

void Terminal::render(const QString &)
{
}

void Terminal::readInput()
{
}

void Terminal::checkSize()
{
}
