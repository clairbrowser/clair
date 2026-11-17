// The runtime suite calls these over DevTools, as a user gesture, which
// chrome.management.uninstall needs to ask.

// Whether an extension with this name is installed.
async function isInstalled(name) {
  const all = await chrome.management.getAll();
  return all.some(extension => extension.name === name);
}

// Asks to remove the extension with this name, without waiting for the
// answer: the dialog stays open until the user answers. `window.outcome`
// becomes "removed" or the error's message.
async function askToRemove(name) {
  const all = await chrome.management.getAll();
  const target = all.find(extension => extension.name === name);
  if (!target) {
    return 'not found';
  }
  window.outcome = undefined;
  chrome.management.uninstall(target.id, {showConfirmDialog: true}).then(
    () => { window.outcome = 'removed'; },
    error => { window.outcome = error.message; });
  return 'asked';
}

// Asks to remove this extension, as askToRemove does.
function askToRemoveSelf() {
  window.outcome = undefined;
  chrome.management.uninstallSelf({showConfirmDialog: true}).then(
    () => { window.outcome = 'removed'; },
    error => { window.outcome = error.message; });
  return 'asked';
}
