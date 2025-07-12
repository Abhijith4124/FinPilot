defmodule Google do
  @moduledoc """
  An OAuth2 strategy for Google.
  """
  use OAuth2.Strategy

  @google_scopes "https://www.googleapis.com/auth/userinfo.email https://www.googleapis.com/auth/userinfo.profile https://www.googleapis.com/auth/calendar https://www.googleapis.com/auth/gmail.modify"

  def client do
    OAuth2.Client.new([
      strategy: __MODULE__,
      client_id: Application.get_env(:finpilot, Google)[:client_id],
      client_secret: Application.get_env(:finpilot, Google)[:client_secret],
      redirect_uri: Application.get_env(:finpilot, Google)[:redirect_uri],
      site: "https://accounts.google.com",
      authorize_url: "https://accounts.google.com/o/oauth2/v2/auth",
      token_url: "https://oauth2.googleapis.com/token"
    ])
    |> OAuth2.Client.put_serializer("application/json", Jason)
  end

  def authorize_url do
    try do
      redirect_url = OAuth2.Client.authorize_url!(client(),
        scope: @google_scopes,
        access_type: "offline",
        prompt: "consent"
      )
      {:ok, redirect_url}
    rescue
      _ ->
        {:error, "Unable to connect to Google. Please try again later."}
    end
  end

  def get_access_token(params \\ [], headers \\ [], opts \\ []) do
    try do
      {:ok, OAuth2.Client.get_token!(client(), params, headers, opts)}
    rescue
      _ ->
        {:error, "Unable to get access token from Google. Please try again later."}
    end
  end

  # Strategy Callbacks

  def authorize_url(client, params) do
    OAuth2.Strategy.AuthCode.authorize_url(client, params)
  end

  def get_token(client, params, headers) do
    client
    |> put_header("accept", "application/json")
    |> OAuth2.Strategy.AuthCode.get_token(params, headers)
  end
end
