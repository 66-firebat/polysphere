# PolySphere Build
#
# Build kbd-capture:    make
# Clean build artifacts: make clean

CC       := gcc
CFLAGS   := -O2 -Wall -Wextra
TARGET   := lib/kbd-capture
SRC      := lib/kbd-capture.c

.PHONY: all clean

all: $(TARGET)

$(TARGET): $(SRC)
	$(CC) $(CFLAGS) -o $@ $<

clean:
	rm -f $(TARGET)
