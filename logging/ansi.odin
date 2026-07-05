package logging

ANSI_RESET :: "\x1b[0m"
ANSI_BOLD  :: "\x1b[1m"
ANSI_ITALIC :: "\x1b[3m"

ANSI_BLACK   :: "\x1b[30m"
ANSI_RED     :: "\x1b[31m"
ANSI_GREEN   :: "\x1b[32m"
ANSI_YELLOW  :: "\x1b[33m"
ANSI_BLUE    :: "\x1b[34m"
ANSI_MAGENTA :: "\x1b[35m"
ANSI_CYAN    :: "\x1b[36m"
ANSI_WHITE   :: "\x1b[37m"

ANSI_GRAY           :: "\x1b[90m"
ANSI_BRIGHT_RED     :: "\x1b[91m"
ANSI_BRIGHT_GREEN   :: "\x1b[92m"
ANSI_BRIGHT_YELLOW  :: "\x1b[93m"
ANSI_BRIGHT_BLUE    :: "\x1b[94m"
ANSI_BRIGHT_MAGENTA :: "\x1b[95m"
ANSI_BRIGHT_CYAN    :: "\x1b[96m"
ANSI_BRIGHT_WHITE   :: "\x1b[97m"

ANSI_TRUECOLOR_FORMAT :: "\x1b[38;2;%d;%d;%dm"

// Bold combined colors
ANSI_BOLD_GRAY   :: "\x1b[1;90m"
ANSI_BOLD_WHITE  :: "\x1b[1;37m"
ANSI_BOLD_YELLOW :: "\x1b[1;33m"
ANSI_BOLD_RED    :: "\x1b[1;31m"
