// Closes the window named in the popup's URL. The request reaches the browser
// just before the page finishes its first load, so the window closes while the
// popup is still loading.
const windowID = Number(new URLSearchParams(location.search).get('window'));
if (windowID) {
  chrome.windows.remove(windowID);
}
