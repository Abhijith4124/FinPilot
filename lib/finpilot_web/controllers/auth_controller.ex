defmodule FinpilotWeb.AuthController do
  use FinpilotWeb, :controller
  alias Finpilot.Accounts

  # Function to validate access token and check granted scopes
  def validate_token_scopes(access_token) do
    client = OAuth2.Client.new([
      site: "https://www.googleapis.com",
      token: %OAuth2.AccessToken{access_token: access_token}
    ])

    case OAuth2.Client.get(client, "/oauth2/v3/tokeninfo?access_token=#{access_token}") do
      {:ok, %OAuth2.Response{status_code: 200, body: token_info_json}} ->
        token_info = Jason.decode!(token_info_json)
        granted_scopes = String.split(Map.get(token_info, "scope", ""), " ")

        # Check for specific permissions
        permissions = %{
          gmail_read: Enum.any?(granted_scopes, &String.contains?(&1, "gmail")),
          gmail_write: Enum.any?(granted_scopes, &String.contains?(&1, "gmail.modify")),
          calendar_access: Enum.any?(granted_scopes, &String.contains?(&1, "calendar"))
        }

        {:ok, permissions, granted_scopes}
      {:ok, %OAuth2.Response{status_code: status_code}} ->
        {:error, "Token validation failed with status: #{status_code}"}
      {:error, reason} ->
        {:error, "Network error: #{inspect(reason)}"}
    end
  end

  def google_callback(conn, %{"code" => code}) do

    with {:ok, client} <- Google.get_access_token(code: code),
         %OAuth2.AccessToken{
            access_token: access_token,
            refresh_token: refresh_token,
            expires_at: expires_at
          } <- client.token do
      case OAuth2.Client.get(client, "https://www.googleapis.com/oauth2/v2/userinfo") do
        {:ok, %OAuth2.Response{body: user_info}} ->
          user_email = user_info["email"]
          user_name = user_info["name"]
          user_picture = user_info["picture"]
          user_verified_email = user_info["verified_email"]

          # Validate token scopes to check what permissions were granted
          permissions = case validate_token_scopes(access_token) do
            {:ok, perms, _granted_scopes} -> perms
            {:error, _reason} -> %{gmail_read: false, gmail_write: false, calendar_access: false}
          end

          # Process user and create session
          conn
          |> process_user_and_create_session(
            user_email, user_name, user_picture, user_verified_email,
            access_token, refresh_token, expires_at, permissions
          )
          |> put_flash(:info, "Successfully signed in with Google!")
          |> redirect(to: "/")

        {:error, _error} ->
          conn
          |> put_flash(:error, "Failed to get user information from Google")
          |> redirect(to: "/")
      end
    else
      {:error, reason} ->
        conn
        |> put_flash(:error, "Authentication failed: #{reason}")
        |> redirect(to: "/")
    end
  end

  def google_callback(conn, _params) do
    conn
    |> put_flash(:error, "Authentication failed: No authorization code received")
    |> redirect(to: "/")
  end

  def signout(conn, _params) do
    conn
    |> clear_session()
    |> put_flash(:info, "You have been signed out")
    |> redirect(to: "/")
  end

  # Private helper function to process user and create session
  defp process_user_and_create_session(conn, user_email, user_name, user_picture, user_verified_email, access_token, refresh_token, expires_at, permissions) do
    # Convert expires_at to DateTime if it's an integer timestamp
    expiry_datetime = case expires_at do
      timestamp when is_integer(timestamp) -> DateTime.from_unix!(timestamp)
      datetime -> datetime
    end

    # Prepare user attributes (username will be auto-derived from email)
    user_attrs = %{
      email: user_email,
      name: user_name,
      picture: user_picture,
      verified: user_verified_email,
      google_access_token: access_token,
      google_refresh_token: refresh_token,
      google_expiry: expiry_datetime,
      gmail_read: permissions.gmail_read,
      gmail_write: permissions.gmail_write,
      calendar_read: permissions.calendar_access,
      calendar_write: permissions.calendar_access,
      hubspot: false
    }

    # Find or create user in database
    user = case Accounts.get_user_by_email(user_email) do
      nil ->
        {:ok, new_user} = Accounts.create_user(user_attrs)
        new_user
      existing_user ->
        {:ok, updated_user} = Accounts.update_user(existing_user, user_attrs)
        updated_user
    end

    # Create session user struct
    current_session_user = %FinpilotWeb.Structs.CurrentSessionUser{
      id: user.id,
      username: user.username,
      email: user.email,
      name: user.name,
      picture: user.picture,
      verified: user.verified,
      google:
        FinpilotWeb.Structs.CurrentSessionUser.new_google_tokens(
          user.google_access_token,
          user.google_refresh_token,
          user.google_expiry
        ),
      connection_permissions:
        FinpilotWeb.Structs.CurrentSessionUser.new_connection_permissions(
          user.gmail_read,
          user.gmail_write,
          user.calendar_read,
          user.calendar_write,
          user.hubspot
        )
    }

    put_session(conn, :current_user, current_session_user)
  end
end
