defmodule Jump.Gmail.Client do
  @moduledoc """
  Gmail API client using GoogleApi.Gmail.V1 with OAuth token injection.
  """

  alias Jump.Accounts
  alias Jump.Auth.GoogleTokens
  require Logger

  @base_url "https://www.googleapis.com/gmail/v1"

  @doc """
  Get a Gmail API client with OAuth token for a user.
  Automatically refreshes the token if it's expired or expiring soon.
  """
  def get_conn(user_id) do
    case Accounts.get_oauth_account(user_id, :google) do
      {:ok, oauth_account} ->
        # Refresh token if needed (expires within 5 min)
        case GoogleTokens.refresh_if_needed(oauth_account) do
          {:ok, refreshed_account} ->
            {:ok, build_conn(refreshed_account.access_token)}

          {:error, reason} ->
            Logger.error("Failed to refresh Google token for user #{user_id}: #{inspect(reason)}")
            {:error, reason}
        end

      {:error, :not_found} ->
        {:error, :google_not_connected}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Build a GoogleApi connection with OAuth token.
  """
  def build_conn(access_token) do
    GoogleApi.Gmail.V1.Connection.new(access_token)
  end

  @doc """
  List messages in user's mailbox with optional query.
  """
  def list_messages(conn, opts \\ []) do
    query = Keyword.get(opts, :query, "")
    max_results = Keyword.get(opts, :max_results, 100)
    page_token = Keyword.get(opts, :page_token, nil)

    params = %{
      "userId" => "me",
      "maxResults" => max_results,
      "q" => query
    }

    params =
      if page_token do
        Map.put(params, "pageToken", page_token)
      else
        params
      end

    case GoogleApi.Gmail.V1.Api.Users.gmail_users_messages_list(conn, "me", Map.to_list(params)) do
      {:ok, %{messages: messages, nextPageToken: next_page_token}} ->
        {:ok, %{messages: messages, next_page_token: next_page_token}}

      {:ok, %{messages: messages}} ->
        {:ok, %{messages: messages, next_page_token: nil}}

      {:ok, empty_response} when empty_response == %{} ->
        {:ok, %{messages: [], next_page_token: nil}}

      {:error, reason} ->
        Logger.error("Failed to list Gmail messages: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Get a full message by ID with specified format.
  """
  def get_message(conn, message_id, opts \\ []) do
    format = Keyword.get(opts, :format, "full")
    headers = Keyword.get(opts, :headers, true)

    params = %{
      "userId" => "me",
      "id" => message_id,
      "format" => format
    }

    params =
      if headers do
        Map.put(params, "metadataHeaders", [
          "From",
          "To",
          "Cc",
          "Bcc",
          "Date",
          "Subject",
          "Message-ID",
          "References",
          "In-Reply-To",
          "Thread-ID"
        ])
      else
        params
      end

    case GoogleApi.Gmail.V1.Api.Users.gmail_users_messages_get(
           conn,
           "me",
           message_id,
           Map.to_list(params)
         ) do
      {:ok, message} ->
        {:ok, message}

      {:error, reason} ->
        Logger.error("Failed to get Gmail message #{message_id}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Send a message via Gmail API.
  """
  def send_message(conn, raw_message, opts \\ []) do
    message_model = %GoogleApi.Gmail.V1.Model.Message{
      raw: raw_message
    }

    case GoogleApi.Gmail.V1.Api.Users.gmail_users_messages_send(conn, "me", body: message_model) do
      {:ok, message} ->
        {:ok, message}

      {:error, reason} ->
        Logger.error("Failed to send Gmail message: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Get message history for incremental sync.
  """
  def get_history(conn, history_id, opts \\ []) do
    history_types = Keyword.get(opts, :history_types, [])
    max_results = Keyword.get(opts, :max_results, 100)
    page_token = Keyword.get(opts, :page_token, nil)

    params = %{
      "userId" => "me",
      "startHistoryId" => history_id,
      "maxResults" => max_results
    }

    params =
      if history_types != [] do
        Map.put(params, "historyTypes", Enum.join(history_types, ","))
      else
        params
      end

    params =
      if page_token do
        Map.put(params, "pageToken", page_token)
      else
        params
      end

    case GoogleApi.Gmail.V1.Api.Users.gmail_users_history_list(conn, "me", params) do
      {:ok, %{history: history, next_page_token: next_page_token, history_id: latest_history_id}} ->
        {:ok,
         %{history: history, next_page_token: next_page_token, history_id: latest_history_id}}

      {:ok, %{history: history}} ->
        {:ok, %{history: history, next_page_token: nil, history_id: nil}}

      {:ok, empty_response} when empty_response == %{} ->
        {:ok, %{history: [], next_page_token: nil, history_id: nil}}

      {:error, reason} ->
        Logger.error("Failed to get Gmail history: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Watch for mailbox changes (push notifications).
  """
  def watch_mailbox(conn, topic_name, opts \\ []) do
    label_ids = Keyword.get(opts, :label_ids, [])

    watch_request = %GoogleApi.Gmail.V1.Model.WatchRequest{
      topicName: topic_name,
      labelIds: label_ids
    }

    case GoogleApi.Gmail.V1.Api.Users.gmail_users_watch(conn, "me", body: watch_request) do
      {:ok, %{historyId: history_id, expiration: expiration}} ->
        {:ok, %{history_id: history_id, expiration: expiration}}

      {:error, reason} ->
        Logger.error("Failed to watch Gmail mailbox: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Stop watching for mailbox changes.
  """
  def stop_watching(conn) do
    case GoogleApi.Gmail.V1.Api.Users.gmail_users_stop(conn, "me") do
      {:ok, _} ->
        :ok

      {:error, reason} ->
        Logger.error("Failed to stop watching Gmail mailbox: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Get thread by ID.
  """
  def get_thread(conn, thread_id, opts \\ []) do
    format = Keyword.get(opts, :format, "full")
    max_results = Keyword.get(opts, :max_results, 100)

    params = %{
      "userId" => "me",
      "id" => thread_id,
      "format" => format,
      "maxResults" => max_results
    }

    case GoogleApi.Gmail.V1.Api.Users.gmail_users_threads_get(conn, "me", thread_id, params) do
      {:ok, thread} ->
        {:ok, thread}

      {:error, reason} ->
        Logger.error("Failed to get Gmail thread #{thread_id}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Modify labels on a message.
  """
  def modify_message_labels(conn, message_id, add_labels \\ [], remove_labels \\ []) do
    params = %{
      "userId" => "me",
      "id" => message_id
    }

    modify_request = %GoogleApi.Gmail.V1.Model.ModifyMessageRequest{
      addLabelIds: add_labels,
      removeLabelIds: remove_labels
    }

    case GoogleApi.Gmail.V1.Api.Users.gmail_users_messages_modify(conn, "me", message_id,
           body: modify_request
         ) do
      {:ok, message} ->
        {:ok, message}

      {:error, reason} ->
        Logger.error("Failed to modify Gmail message labels: #{inspect(reason)}")
        {:error, reason}
    end
  end
end
