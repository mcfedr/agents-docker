export IT2_TAB_COLOR=default
function set_tab_color() {
  it2_tab_color "$IT2_TAB_COLOR"
}

it2_tab_color() {
  if [ "$1" = "default" ] || [ "$1" = "" ]; then
    echo -ne "\033]6;1;bg;*;default\a"
    return
  fi

  hex="$1"
  # Get hex values for each channel and convert to decimal
  R="$((16#${hex:0:2}))"
  G="$((16#${hex:2:2}))"
  B="$((16#${hex:4}))"
  echo -ne "\033]6;1;bg;red;brightness;$R\a"
  echo -ne "\033]6;1;bg;green;brightness;$G\a"
  echo -ne "\033]6;1;bg;blue;brightness;$B\a"
}

precmd_functions+=(set_tab_color)
