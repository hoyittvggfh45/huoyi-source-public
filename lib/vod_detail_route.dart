enum VodOpenAction { detail, directPlayback }

VodOpenAction vodOpenAction({required bool isVodZone, required bool resume}) {
  if (!resume && isVodZone) return VodOpenAction.detail;
  return VodOpenAction.directPlayback;
}
