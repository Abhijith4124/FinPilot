defmodule FinpilotWeb.LandingPageLive.Index do
  use FinpilotWeb, :live_view

  alias Finpilot.LandingPageContext
  alias Finpilot.LandingPageContext.LandingPage

  @impl true
  def mount(_params, _session, socket) do
    current_user = socket.assigns[:current_user]
    {:ok, assign(socket, :current_user, current_user)}
  end

  def handle_params(_params, _uri, socket) do
    {:noreply, socket}
  end
end
