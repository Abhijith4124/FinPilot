defmodule FinpilotWeb.LandingPageLive.Index do
  use FinpilotWeb, :live_view
  alias Finpilot.Accounts
  alias FinpilotWeb.Structs.CurrentSessionUser

  @impl true
  def mount(_params, session, socket) do
    current_user = validate_session_user(session["current_user"])
    {:ok, assign(socket, current_user: current_user, show_settings: false)}
  end

  # Private function to validate that the session user exists in the database
  defp validate_session_user(nil), do: nil
  defp validate_session_user(%{email: email}) do
    case Accounts.get_user_by_email(email) do
      nil -> nil  # User doesn't exist in database, clear session
      db_user ->
        # Create proper CurrentSessionUser struct with all required fields
        %CurrentSessionUser{
          id: db_user.id,
          username: db_user.username,
          email: db_user.email,
          name: db_user.name,
          picture: db_user.picture,
          verified: db_user.verified,
          connection_permissions: CurrentSessionUser.new_connection_permissions(
            db_user.gmail_read,
            db_user.gmail_write,
            db_user.calendar_read,
            db_user.calendar_write,
            db_user.hubspot
          )
        }
    end
  end
  defp validate_session_user(_), do: nil

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

  @impl true
  def handle_event("toggle_settings", _params, socket) do
    {:noreply, assign(socket, :show_settings, !socket.assigns.show_settings)}
  end

  @impl true
  def handle_event("grant_permission", %{"service" => service}, socket) do
    # Handle permission granting logic here
    case service do
      "gmail" ->
        case Google.authorize_url(["https://www.googleapis.com/auth/gmail.modify"]) do
          {:ok, redirect_url} ->
            {:noreply, redirect(socket, external: redirect_url)}
          {:error, error} ->
            socket = socket |> put_flash(:error, "Failed to authorize Gmail: #{error}")
            {:noreply, socket}
        end
      "calendar" ->
        case Google.authorize_url(["https://www.googleapis.com/auth/calendar"]) do
          {:ok, redirect_url} ->
            {:noreply, redirect(socket, external: redirect_url)}
          {:error, error} ->
            socket = socket |> put_flash(:error, "Failed to authorize Calendar: #{error}")
            {:noreply, socket}
        end
      "hubspot" ->
        case Hubspot.authorize_url() do
          {:ok, redirect_url} ->
            {:noreply, redirect(socket, external: redirect_url)}
          {:error, error} ->
            socket = socket |> put_flash(:error, "Failed to authorize HubSpot: #{error}")
            {:noreply, socket}
        end
      _ ->
        {:noreply, socket}
    end
  end
end
