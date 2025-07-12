defmodule Finpilot.Services.Hubspot do
  @moduledoc """
  HubSpot API service for managing contacts and other CRM operations.
  """

  alias Finpilot.Accounts.User

  @base_url "https://api.hubapi.com"

  @doc """
  Gets all contacts from HubSpot.
  """
  def get_contacts(%User{} = user, opts \\ []) do
    with {:ok, access_token} <- get_valid_access_token(user) do
      limit = Keyword.get(opts, :limit, 100)
      
      url = "#{@base_url}/crm/v3/objects/contacts?limit=#{limit}"
      headers = ["Authorization": "Bearer #{access_token}", "Content-Type": "application/json"]
      
      case Finch.build(:get, url, headers) |> Finch.request(Finpilot.Finch) do
        {:ok, %Finch.Response{status: 200, body: body}} ->
          {:ok, Jason.decode!(body)}
        {:ok, %Finch.Response{status: status, body: body}} ->
          {:error, "HubSpot API error: #{status} - #{body}"}
        {:error, reason} ->
          {:error, "Network error: #{inspect(reason)}"}
      end
    end
  end

  @doc """
  Creates a new contact in HubSpot.
  """
  def create_contact(%User{} = user, contact_data) do
    with {:ok, access_token} <- get_valid_access_token(user) do
      url = "#{@base_url}/crm/v3/objects/contacts"
      headers = ["Authorization": "Bearer #{access_token}", "Content-Type": "application/json"]
      
      body = Jason.encode!(%{
        "properties" => contact_data
      })
      
      case Finch.build(:post, url, headers, body) |> Finch.request(Finpilot.Finch) do
        {:ok, %Finch.Response{status: 201, body: response_body}} ->
          {:ok, Jason.decode!(response_body)}
        {:ok, %Finch.Response{status: status, body: response_body}} ->
          {:error, "HubSpot API error: #{status} - #{response_body}"}
        {:error, reason} ->
          {:error, "Network error: #{inspect(reason)}"}
      end
    end
  end

  @doc """
  Updates an existing contact in HubSpot.
  """
  def update_contact(%User{} = user, contact_id, contact_data) do
    with {:ok, access_token} <- get_valid_access_token(user) do
      url = "#{@base_url}/crm/v3/objects/contacts/#{contact_id}"
      headers = ["Authorization": "Bearer #{access_token}", "Content-Type": "application/json"]
      
      body = Jason.encode!(%{
        "properties" => contact_data
      })
      
      case Finch.build(:patch, url, headers, body) |> Finch.request(Finpilot.Finch) do
        {:ok, %Finch.Response{status: 200, body: response_body}} ->
          {:ok, Jason.decode!(response_body)}
        {:ok, %Finch.Response{status: status, body: response_body}} ->
          {:error, "HubSpot API error: #{status} - #{response_body}"}
        {:error, reason} ->
          {:error, "Network error: #{inspect(reason)}"}
      end
    end
  end

  @doc """
  Searches for contacts in HubSpot.
  """
  def search_contacts(%User{} = user, search_query, opts \\ []) do
    with {:ok, access_token} <- get_valid_access_token(user) do
      limit = Keyword.get(opts, :limit, 100)
      
      url = "#{@base_url}/crm/v3/objects/contacts/search"
      headers = ["Authorization": "Bearer #{access_token}", "Content-Type": "application/json"]
      
      body = Jason.encode!(%{
        "filterGroups" => [
          %{
            "filters" => [
              %{
                "propertyName" => "email",
                "operator" => "CONTAINS_TOKEN",
                "value" => search_query
              }
            ]
          }
        ],
        "limit" => limit
      })
      
      case Finch.build(:post, url, headers, body) |> Finch.request(Finpilot.Finch) do
        {:ok, %Finch.Response{status: 200, body: response_body}} ->
          {:ok, Jason.decode!(response_body)}
        {:ok, %Finch.Response{status: status, body: response_body}} ->
          {:error, "HubSpot API error: #{status} - #{response_body}"}
        {:error, reason} ->
          {:error, "Network error: #{inspect(reason)}"}
      end
    end
  end

  @doc """
  Gets a specific contact by ID from HubSpot.
  """
  def get_contact(%User{} = user, contact_id) do
    with {:ok, access_token} <- get_valid_access_token(user) do
      url = "#{@base_url}/crm/v3/objects/contacts/#{contact_id}"
      headers = ["Authorization": "Bearer #{access_token}", "Content-Type": "application/json"]
      
      case Finch.build(:get, url, headers) |> Finch.request(Finpilot.Finch) do
        {:ok, %Finch.Response{status: 200, body: body}} ->
          {:ok, Jason.decode!(body)}
        {:ok, %Finch.Response{status: 404}} ->
          {:error, "Contact not found"}
        {:ok, %Finch.Response{status: status, body: body}} ->
          {:error, "HubSpot API error: #{status} - #{body}"}
        {:error, reason} ->
          {:error, "Network error: #{inspect(reason)}"}
      end
    end
  end

  # Private function to get a valid access token, refreshing if necessary
  defp get_valid_access_token(%User{} = user) do
    if User.has_valid_hubspot_tokens?(user) do
      {:ok, user.hubspot_access_token}
    else
      case user.hubspot_refresh_token do
        nil ->
          {:error, "No HubSpot refresh token available. Please reconnect your HubSpot account."}
        refresh_token ->
          refresh_access_token(user, refresh_token)
      end
    end
  end

  # Private function to refresh the access token
  defp refresh_access_token(%User{} = user, refresh_token) do
    url = "#{@base_url}/oauth/v1/token"
    headers = ["Content-Type": "application/x-www-form-urlencoded"]
    
    body = URI.encode_query(%{
      "grant_type" => "refresh_token",
      "client_id" => Application.get_env(:finpilot, Hubspot)[:client_id],
      "client_secret" => Application.get_env(:finpilot, Hubspot)[:client_secret],
      "refresh_token" => refresh_token
    })
    
    case Finch.build(:post, url, headers, body) |> Finch.request(Finpilot.Finch) do
      {:ok, %Finch.Response{status: 200, body: response_body}} ->
        case Jason.decode(response_body) do
          {:ok, %{"access_token" => new_access_token, "expires_in" => expires_in}} ->
            # Calculate new expiry time
            new_expiry = DateTime.add(DateTime.utc_now(), expires_in, :second)
            
            # Update user with new token
            case Finpilot.Accounts.update_hubspot_tokens(user, new_access_token, refresh_token, new_expiry, user.hubspot_portal_id) do
              {:ok, _updated_user} ->
                {:ok, new_access_token}
              {:error, _changeset} ->
                {:error, "Failed to save refreshed token"}
            end
          {:error, _} ->
            {:error, "Invalid response from HubSpot token refresh"}
        end
      {:ok, %Finch.Response{status: status, body: body}} ->
        {:error, "Token refresh failed: #{status} - #{body}"}
      {:error, reason} ->
        {:error, "Network error during token refresh: #{inspect(reason)}"}
    end
  end
end