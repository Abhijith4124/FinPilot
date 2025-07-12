defmodule Hubspot do
  @moduledoc """
  An OAuth2 strategy for HubSpot.
  """
  use OAuth2.Strategy

  @hubspot_scopes "crm.objects.contacts.read crm.objects.contacts.write crm.schemas.contacts.read crm.schemas.contacts.write"

  def client do
    config = Application.get_env(:finpilot, HubSpot)

    OAuth2.Client.new([
      strategy: __MODULE__,
      client_id: config[:client_id],
      client_secret: config[:client_secret],
      redirect_uri: config[:redirect_uri],
      site: "https://api.hubapi.com",
      authorize_url: "https://app.hubspot.com/oauth/authorize",
      token_url: "https://api.hubapi.com/oauth/v1/token"
    ])
    |> OAuth2.Client.put_serializer("application/json", Jason)
    |> OAuth2.Client.put_serializer("application/x-www-form-urlencoded", OAuth2.Client.Serializer.Form)
  end

  def authorize_url do
    try do
      redirect_url = OAuth2.Client.authorize_url!(client(),
        scope: @hubspot_scopes
      )
      {:ok, redirect_url}
    rescue
      _ ->
        {:error, "Unable to connect to HubSpot. Please try again later."}
    end
  end

  def authorize_url(custom_scopes) when is_list(custom_scopes) do
    try do
      scope_string = Enum.join(custom_scopes, " ")
      redirect_url = OAuth2.Client.authorize_url!(client(),
        scope: scope_string
      )
      {:ok, redirect_url}
    rescue
      _ ->
        {:error, "Unable to connect to HubSpot. Please try again later."}
    end
  end

  def get_access_token(params \\ [], headers \\ [], opts \\ []) do
    case OAuth2.Client.get_token(client(), params, headers, opts) do
      {:ok, client} ->
        {:ok, client}
      {:error, %OAuth2.Response{status_code: status_code, body: body}} ->
        error_msg = case body do
          %{"error" => error, "error_description" => desc} -> "#{error}: #{desc}"
          %{"error" => error} -> error
          _ -> "HTTP #{status_code}: Token request failed"
        end
        {:error, "HubSpot authentication failed: #{error_msg}"}
      {:error, %OAuth2.Error{reason: reason}} ->
        {:error, "Network error: #{inspect(reason)}"}
      {:error, reason} ->
        {:error, "Unable to get access token from HubSpot: #{inspect(reason)}"}
    end
  end

  # Strategy Callbacks

  def authorize_url(client, params) do
    OAuth2.Strategy.AuthCode.authorize_url(client, params)
  end

  def get_token(client, params, headers) do
    # Ensure all required parameters are explicitly set
    client
    |> put_header("accept", "application/json")
    |> put_header("content-type", "application/x-www-form-urlencoded")
    |> put_param(:grant_type, "authorization_code")
    |> put_param(:client_id, client.client_id)
    |> put_param(:client_secret, client.client_secret)
    |> put_param(:redirect_uri, client.redirect_uri)
    |> OAuth2.Strategy.AuthCode.get_token(params, headers)
  end
end
