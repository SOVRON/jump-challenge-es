defmodule JumpWeb.AuthController do
  use JumpWeb, :controller

  alias Jump.Accounts

  def request(conn, _params) do
    # Ueberauth middleware handles the OAuth flow before reaching this point
    # This should not be reached unless there's an error
    conn
    |> put_flash(:error, "Authentication failed")
    |> redirect(to: ~p"/")
  end

  def callback(conn, %{"provider" => "google"}) do
    case conn.assigns[:ueberauth_auth] do
      %Ueberauth.Auth{} = auth ->
        handle_google_auth(conn, auth)

      _ ->
        conn
        |> put_flash(:error, "Authentication failed. Please try again.")
        |> redirect(to: ~p"/")
    end
  end

  def callback(conn, %{"provider" => "hubspot"}) do
    case conn.assigns[:ueberauth_auth] do
      %Ueberauth.Auth{} = auth ->
        handle_hubspot_auth(conn, auth)

      _ ->
        conn
        |> put_flash(:error, "HubSpot authentication failed. Please try again.")
        |> redirect(to: ~p"/")
    end
  end

  def callback(conn, %{"provider" => _}) do
    conn
    |> put_flash(:error, "Unsupported provider")
    |> redirect(to: ~p"/")
  end

  def delete(conn, _params) do
    conn
    |> clear_session()
    |> put_flash(:info, "You have been logged out.")
    |> redirect(to: ~p"/")
  end

  defp handle_google_auth(conn, auth) do
    case auth.credentials do
      %{token: access_token, refresh_token: refresh_token, expires_at: expires_at} ->
        _user_info = auth.extra.raw_info
        email = auth.info.email
        name = auth.info.name
        avatar_url = auth.info.image
        external_uid = auth.uid

        # Create or get user
        {:ok, user} =
          Accounts.get_or_create_user_by_email(email, %{
            name: name,
            avatar_url: avatar_url
          })

        # Store OAuth account with encrypted tokens
        oauth_attrs = %{
          user_id: user.id,
          provider: :google,
          access_token: access_token,
          refresh_token: refresh_token,
          token_type: "Bearer",
          expires_at: DateTime.from_unix!(expires_at),
          scope: auth.credentials.scopes |> Enum.join(" "),
          external_uid: external_uid
        }

        case Accounts.upsert_oauth_account(oauth_attrs) do
          {:ok, _oauth_account} ->
            # Enqueue initial Gmail import for RAG indexing
            Jump.Workers.ImportGmailMailbox.import_user_mailbox(user.id)

            conn
            |> put_session(:user_id, user.id)
            |> put_session(:user_email, user.email)
            |> configure_session(renew: true)
            |> put_flash(:info, "Successfully authenticated with Google!")
            |> redirect(to: ~p"/")

          {:error, changeset} ->
            conn
            |> put_flash(:error, "Failed to save OAuth account: #{inspect(changeset.errors)}")
            |> redirect(to: ~p"/")
        end

      _ ->
        conn
        |> put_flash(:error, "Invalid authentication response")
        |> redirect(to: ~p"/")
    end
  end

  defp handle_hubspot_auth(conn, auth) do
    # Get current user from session (HubSpot is added after Google login)
    user_id = get_session(conn, :user_id)
    _user_email = get_session(conn, :user_email)

    if user_id do
      case auth.credentials do
        %{token: access_token, refresh_token: refresh_token, expires_at: expires_at} ->
          # Debug: Log the auth structure to understand what HubSpot returns
          require Logger
          Logger.info("HubSpot Auth Response: #{inspect(auth, pretty: true)}")

          raw_info = auth.extra.raw_info || %{}

          external_uid =
            cond do
              hub_id = raw_info[:hub_id] -> to_string(hub_id)
              hub_id = raw_info["hub_id"] -> to_string(hub_id)
              auth.uid not in [nil, ""] -> to_string(auth.uid)
              true -> nil
            end

          if is_nil(external_uid) or external_uid == "" do
            Logger.error(
              "HubSpot OAuth callback missing hub_id in auth payload: #{inspect(auth, pretty: true)}"
            )

            conn
            |> put_flash(
              :error,
              "HubSpot did not return an account identifier. Please try connecting again."
            )
            |> redirect(to: ~p"/app")
          else
            # Store OAuth account with encrypted tokens
            oauth_attrs = %{
              user_id: user_id,
              provider: :hubspot,
              access_token: access_token,
              refresh_token: refresh_token,
              token_type: "Bearer",
              expires_at: DateTime.from_unix!(expires_at),
              scope: auth.credentials.scopes |> Enum.join(" "),
              external_uid: external_uid
            }

            case Accounts.upsert_oauth_account(oauth_attrs) do
              {:ok, _oauth_account} ->
                # Enqueue initial HubSpot contact import for RAG indexing
                Jump.Workers.ImportHubspotContacts.import_user_contacts(user_id)

                conn
                |> put_flash(:info, "Successfully connected HubSpot account!")
                |> redirect(to: ~p"/app")

              {:error, changeset} ->
                conn
                |> put_flash(
                  :error,
                  "Failed to save HubSpot account: #{inspect(changeset.errors)}"
                )
                |> redirect(to: ~p"/app")
            end
          end

        _ ->
          conn
          |> put_flash(:error, "Invalid HubSpot authentication response")
          |> redirect(to: ~p"/app")
      end
    else
      conn
      |> put_flash(:error, "You must be logged in to connect HubSpot")
      |> redirect(to: ~p"/")
    end
  end
end
