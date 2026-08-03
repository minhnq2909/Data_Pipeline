const dashboardFrame = document.querySelector("#dashboardFrame");
const loadingState = document.querySelector("#loadingState");
const errorState = document.querySelector("#errorState");
const refreshButton = document.querySelector("#refreshButton");

async function loadDashboard() {
  loadingState.hidden = false;
  errorState.hidden = true;
  dashboardFrame.hidden = true;
  refreshButton.disabled = true;

  try {
    const response = await fetch("/api/metabase/guest-token", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ entityType: "dashboard", entityId: 2 }),
    });

    const data = await response.json();
    if (!response.ok) {
      throw new Error(data.error || "Unable to create Metabase guest token");
    }

    dashboardFrame.src = data.iframeUrl;
    dashboardFrame.hidden = false;
  } catch (error) {
    errorState.textContent = error.message;
    errorState.hidden = false;
  } finally {
    loadingState.hidden = true;
    refreshButton.disabled = false;
  }
}

refreshButton.addEventListener("click", loadDashboard);
loadDashboard();
