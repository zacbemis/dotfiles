#!/bin/sh

CUR=$(brightnessctl get)
MAX=$(brightnessctl max)
PERCENT=$((CUR * 100 / MAX))

# Minutes since midnight
H=$(date +%H)
M=$(date +%M)
NOW=$((10#$H * 60 + 10#$M))

# Night window: 17:00 -> 05:00
NIGHT_START=$((17 * 60)) # 17:00
NIGHT_END=$((5 * 60))    # 05:00

# If window crosses midnight, "night" is: NOW >= start OR NOW < end
if [ "$NOW" -ge "$NIGHT_START" ] || [ "$NOW" -lt "$NIGHT_END" ]; then
  ICON=""
else
  ICON="󰃠"
fi

printf "%s%% %s\n" "$PERCENT" "$ICON"
