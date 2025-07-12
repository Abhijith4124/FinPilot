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

  def authorize_url! do
    OAuth2.Client.authorize_url!(client(), scope: @google_scopes)
  end

  # you can pass options to the underlying http library via `opts` parameter
  def get_token!(params \\ [], headers \\ [], opts \\ []) do
    OAuth2.Client.get_token!(client(), params, headers, opts)
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
