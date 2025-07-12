defmodule FinpilotWeb.LandingPageLive.Index do
  use FinpilotWeb, :live_view

  @impl true
  def mount(_params, %{"current_user" => current_user}, socket) do
    {:ok, assign(socket, :current_user, current_user)}
  end

  @impl true
  def handle_params(_params, _uri, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("signin_google", _params, socket) do
    case Google.authorize_url() do
      {:ok, redirect_url} ->
        {:noreply, redirect(socket, external: redirect_url)}
      {:error, error} ->
        socket = socket |> put_flash(:error, error)
        {:noreply, socket}
    end
  end
end
