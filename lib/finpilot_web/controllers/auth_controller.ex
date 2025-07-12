defmodule FinpilotWeb.AuthController do
  use FinpilotWeb, :controller

  def google_callback(conn, %{"code" => code}) do

    with {:ok, client} <- Google.get_access_token(code: code),
         %OAuth2.AccessToken{
            access_token: access_token,
            refresh_token: refresh_token,
            expires_at: expires_at
          } <- client.token do
      case OAuth2.Client.get(client, "https://www.googleapis.com/oauth2/v2/userinfo") do
        {:ok, %OAuth2.Response{body: user_info}} ->
          user_id = user_info["id"]
          user_email = user_info["email"]
          user_name = user_info["name"]
          user_picture = user_info["picture"]
          user_verified_email = user_info["verified_email"]

          current_session_user = %FinpilotWeb.Structs.CurrentSessionUser{
            id: user_id,
            username: user_email,
            email: user_email,
            name: user_name,
            picture: user_picture,
            verified: user_verified_email,
            google:
              FinpilotWeb.Structs.CurrentSessionUser.new_google_tokens(
                access_token,
                refresh_token,
                expires_at
              )
          }

          conn
          |> put_session(:current_user, current_session_user)
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
end
