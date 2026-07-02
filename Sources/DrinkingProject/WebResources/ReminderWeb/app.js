const state = {
  role: "primary",
  remainingSeconds: 30,
  confirmationCount: 0,
  requiredConfirmations: 3,
  buttonVisible: false,
  buttonEnabled: false,
  statusText: "30 秒后再确认",
  hintText: "把杯子拿起来，慢慢喝完这一口。",
  buttonText: "等待中",
  playbackMode: "advanceOnEnd",
  hasPlayableVideo: true,
  isCompact: false,
  isPlaygroundMode: false,
  friendlyMessage: "喝一口水，顺便让眼睛休息一下。",
  testModeText: "测试模式：等待时间已缩短",
  mediaWarningText: "",
  videoMessage: "未找到可播放视频，请检查 视频/视频素材/"
};

const elements = {
  videoWarning: document.getElementById("videoWarning"),
  playbackControl: document.getElementById("playbackControl"),
  testModePill: document.getElementById("testModePill"),
  playbackMode: document.getElementById("playbackModeSelect"),
  role: document.getElementById("screenRole"),
  status: document.getElementById("statusText"),
  countdown: document.getElementById("countdownText"),
  progress: document.getElementById("progressText"),
  button: document.getElementById("confirmButton"),
  hint: document.getElementById("hintText")
};

function formatTime(totalSeconds) {
  const safeSeconds = Math.max(0, Number(totalSeconds) || 0);
  const minutes = Math.floor(safeSeconds / 60);
  const seconds = safeSeconds % 60;
  return `${String(minutes).padStart(2, "0")}:${String(seconds).padStart(2, "0")}`;
}

function applyState(nextState) {
  Object.assign(state, nextState || {});
  const isSecondary = state.role === "secondary";
  const isCompact = Boolean(state.isCompact);

  document.body.classList.toggle("secondary", isSecondary);
  document.body.classList.toggle("compact", isCompact);
  document.body.classList.toggle("no-video", !state.hasPlayableVideo);
  // Compact popup mode never plays a video, so the "no playable video" warning is noise there.
  const warningText = isCompact
    ? ""
    : state.mediaWarningText || (!state.hasPlayableVideo ? state.videoMessage : "");
  elements.videoWarning.hidden = !warningText;
  elements.videoWarning.textContent = warningText;
  elements.playbackControl.hidden = isSecondary || isCompact;
  elements.testModePill.hidden = !state.isPlaygroundMode || isSecondary;
  elements.testModePill.textContent = state.testModeText;
  if (elements.playbackMode.value !== state.playbackMode) {
    elements.playbackMode.value = state.playbackMode;
  }
  elements.role.textContent = isSecondary ? "同步屏幕" : "主屏幕";
  elements.status.textContent = state.statusText;
  elements.countdown.textContent = formatTime(state.remainingSeconds);
  elements.progress.textContent = `确认 ${state.confirmationCount} / ${state.requiredConfirmations}`;
  elements.hint.textContent = isSecondary ? "请在主屏幕完成确认" : (state.hintText || state.friendlyMessage);

  elements.button.hidden = isSecondary || !state.buttonVisible;
  elements.button.disabled = !state.buttonEnabled;
  elements.button.textContent = state.buttonText;
}

function postToSwift(payload) {
  window.webkit?.messageHandlers?.drinkingProject?.postMessage(payload);
}

function canConfirm() {
  return state.role === "primary"
    && !elements.button.hidden
    && !elements.button.disabled
    && Boolean(window.webkit?.messageHandlers?.drinkingProject);
}

function confirmWater() {
  if (!canConfirm()) {
    return;
  }
  postToSwift({ type: "confirmWater" });
}

elements.button.addEventListener("click", confirmWater);

elements.playbackMode.addEventListener("change", () => {
  if (state.role !== "primary") {
    return;
  }
  postToSwift({ type: "setPlaybackMode", mode: elements.playbackMode.value });
});

document.addEventListener("keydown", (event) => {
  if (event.key !== "Enter" || event.repeat) {
    return;
  }
  if (!canConfirm()) {
    return;
  }
  event.preventDefault();
  confirmWater();
});

window.drinkingProjectState = applyState;
applyState(state);
