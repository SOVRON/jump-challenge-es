defmodule JumpWeb.ChatLive do
  use JumpWeb, :live_view

  alias Jump.{Accounts, Agents, Messaging}
  alias Jump.Agent, as: ChatAgent
  alias Jump.Messaging.Conversation

  require Logger

  @conversation_limit 30
  @message_limit 100

  @context_filters [
    %{label: "All meetings", value: "all"},
    %{label: "Prospects", value: "prospects"},
    %{label: "Priority", value: "priority"}
  ]

  @impl true
  def mount(_params, %{"user_id" => user_id}, socket) do
    current_user = Accounts.get_user!(user_id)
    instructions = Agents.list_instructions(user_id)
    oauth_accounts = Accounts.list_oauth_accounts(user_id)

    integration_status = build_integration_status(oauth_accounts)
    missing_integrations = compute_missing_integrations(integration_status)

    conversations = Messaging.list_conversations(user_id, limit: @conversation_limit)
    {selected_conversation, messages} = pick_initial_conversation(user_id, conversations)
    annotated_messages = annotate_messages(messages)

    socket =
      socket
      |> assign(:page_title, "Advisor Agent Chat")
      |> assign(:current_user, current_user)
      |> assign(:instructions, instructions)
      |> assign(:integration_status, integration_status)
      |> assign(:missing_integrations, missing_integrations)
      |> assign(:conversations, conversations)
      |> assign(:selected_conversation, selected_conversation)
      |> assign(:current_scope, nil)
      |> assign(:composer_form, new_composer_form())
      |> assign(:composer_state, %{submitting?: false, error: nil})
      |> assign(:composer_disabled?, composer_disabled?(selected_conversation))
      |> assign(:sidebar_open, false)
      |> assign(:active_tab, :chat)
      |> assign(:context_filters, @context_filters)
      |> assign(:active_context, hd(@context_filters))
      |> assign(:empty_state, Enum.empty?(annotated_messages))

    {:ok, stream(socket, :messages, annotated_messages)}
  end

  def mount(_params, _session, socket) do
    {:ok, push_navigate(socket, to: ~p"/")}
  end

  @impl true
  def handle_event("start_new_conversation", _params, socket) do
    socket =
      socket
      |> assign(:selected_conversation, nil)
      |> assign(:composer_form, new_composer_form())
      |> assign(:composer_state, %{submitting?: false, error: nil})
      |> assign(:composer_disabled?, false)
      |> assign(:empty_state, true)
      |> stream(:messages, [], reset: true)

    {:noreply, socket}
  end

  def handle_event("toggle_sidebar", _params, socket) do
    {:noreply, update(socket, :sidebar_open, &(!&1))}
  end

  def handle_event(
        "select_conversation",
        %{"id" => conversation_id},
        %{assigns: assigns} = socket
      ) do
    user_id = assigns.current_user.id

    with {:ok, _scope, _source_id} <- Messaging.parse_conversation_identifier(conversation_id),
         {:ok, messages} <-
           Messaging.get_conversation_messages_by_id(user_id, conversation_id,
             limit: @message_limit
           ),
         {:ok, conversation} <- Messaging.get_conversation_summary(user_id, conversation_id) do
      annotated_messages = annotate_messages(messages)

      socket =
        socket
        |> assign(:selected_conversation, conversation)
        |> assign(:composer_state, %{submitting?: false, error: nil})
        |> assign(:composer_form, new_composer_form())
        |> assign(:composer_disabled?, composer_disabled?(conversation))
        |> assign(:empty_state, Enum.empty?(annotated_messages))
        |> assign(:sidebar_open, false)
        |> stream(:messages, annotated_messages, reset: true)

      {:noreply, socket}
    else
      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("toggle_instruction", %{"id" => instruction_id}, %{assigns: assigns} = socket) do
    user_id = assigns.current_user.id

    with {id, ""} <- Integer.parse(instruction_id),
         instruction when not is_nil(instruction) <-
           Enum.find(assigns.instructions, &(&1.id == id)),
         true <- instruction.user_id == user_id,
         {:ok, updated_instruction} <-
           toggle_instruction_record(instruction) do
      instructions =
        Enum.map(assigns.instructions, fn
          %{id: ^id} -> updated_instruction
          other -> other
        end)

      {:noreply, assign(socket, :instructions, instructions)}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event(
        "send_message",
        %{"chat" => %{"content" => content}},
        %{assigns: assigns} = socket
      ) do
    trimmed = content |> to_string() |> String.trim()

    if trimmed == "" do
      socket =
        socket
        |> assign(:composer_form, to_form(%{"content" => content}, as: :chat))
        |> assign(:composer_state, %{submitting?: false, error: "Type a message to continue."})

      {:noreply, socket}
    else
      user_id = assigns.current_user.id
      thread_id = derive_thread_id(assigns.selected_conversation)
      socket = assign(socket, :composer_state, %{submitting?: true, error: nil})

      case ChatAgent.process_message(user_id, trimmed, thread_id) do
        {:ok, _assistant_message, _tool_messages} ->
          conversation_id = "thread:#{thread_id}"

          {:ok, messages} =
            Messaging.get_conversation_messages_by_id(user_id, conversation_id,
              limit: @message_limit
            )

          {:ok, conversation} =
            Messaging.get_conversation_summary(user_id, conversation_id)

          conversations = Messaging.list_conversations(user_id, limit: @conversation_limit)
          annotated_messages = annotate_messages(messages)

          socket =
            socket
            |> assign(:conversations, conversations)
            |> assign(:selected_conversation, conversation)
            |> assign(:composer_form, new_composer_form())
            |> assign(:composer_state, %{submitting?: false, error: nil})
            |> assign(:composer_disabled?, composer_disabled?(conversation))
            |> assign(:empty_state, Enum.empty?(annotated_messages))
            |> assign(:sidebar_open, false)
            |> stream(:messages, annotated_messages, reset: true)

          {:noreply, socket}

        {:error, reason} ->
          socket =
            socket
            |> assign(:composer_form, to_form(%{"content" => content}, as: :chat))
            |> assign(:composer_state, %{submitting?: false, error: format_error(reason)})

          {:noreply, socket}
      end
    end
  end

  def handle_event("composer_updated", %{"chat" => chat_params}, socket) do
    socket =
      socket
      |> assign(:composer_form, to_form(chat_params, as: :chat))
      |> assign(:composer_state, %{submitting?: false, error: nil})

    {:noreply, socket}
  end

  def handle_event("set_tab", %{"tab" => "chat"}, socket),
    do: {:noreply, assign(socket, :active_tab, :chat)}

  def handle_event("set_tab", %{"tab" => "history"}, socket),
    do: {:noreply, assign(socket, :active_tab, :history)}

  def handle_event("set_tab", _params, socket), do: {:noreply, socket}

  def handle_event("set_context", %{"value" => value}, socket) do
    selected =
      Enum.find(@context_filters, hd(@context_filters), fn filter ->
        filter.value == value
      end)

    {:noreply, assign(socket, :active_context, selected)}
  end

  defp pick_initial_conversation(_user_id, []), do: {nil, []}

  defp pick_initial_conversation(user_id, [conversation | _]) do
    case Messaging.get_conversation_messages_by_id(user_id, conversation.id,
           limit: @message_limit
         ) do
      {:ok, messages} ->
        {conversation, messages}

      {:error, _reason} ->
        {conversation, []}
    end
  end

  defp annotate_messages(messages) do
    {annotated, _} =
      Enum.map_reduce(messages, nil, fn message, last_date ->
        label = message.inserted_at |> to_date_label()
        new_section? = label != last_date

        entry = %{
          id: "message-#{message.id}",
          message: message,
          date_label: label,
          new_date?: new_section?
        }

        {entry, label}
      end)

    annotated
  end

  defp to_date_label(%NaiveDateTime{} = naive) do
    {:ok, dt} = DateTime.from_naive(naive, "Etc/UTC")
    today = Date.utc_today()
    message_date = DateTime.to_date(dt)

    cond do
      message_date == today ->
        "Today"

      Date.compare(message_date, Date.add(today, -1)) == :eq ->
        "Yesterday"

      Date.compare(message_date, Date.add(today, -6)) != :lt ->
        Calendar.strftime(message_date, "%A")

      true ->
        Calendar.strftime(message_date, "%B %-d")
    end
  end

  defp new_composer_form do
    to_form(%{"content" => ""}, as: :chat)
  end

  defp build_integration_status(accounts) do
    Enum.reduce(accounts, %{google: false, hubspot: false}, fn account, acc ->
      Map.put(acc, account.provider, true)
    end)
  end

  defp compute_missing_integrations(status) do
    status
    |> Enum.filter(fn {_provider, connected?} -> not connected? end)
    |> Enum.map(&elem(&1, 0))
  end

  defp toggle_instruction_record(%{enabled: true} = instruction) do
    Agents.disable_instruction(instruction)
  end

  defp toggle_instruction_record(%{enabled: false} = instruction) do
    Agents.enable_instruction(instruction)
  end

  defp composer_disabled?(nil), do: false
  defp composer_disabled?(%Conversation{scope: scope}) when scope in [:task, :orphan], do: true
  defp composer_disabled?(%Conversation{}), do: false

  defp derive_thread_id(%Conversation{scope: :thread, thread_id: thread_id})
       when is_binary(thread_id) do
    thread_id
  end

  defp derive_thread_id(_), do: ChatAgent.generate_thread_id()

  defp format_error(reason) when is_binary(reason) do
    Logger.warning("Chat error displayed to user", error: reason)
    reason
  end

  defp format_error(reason) do
    error_msg = "Failed to process message: #{inspect(reason)}"

    Logger.warning("Chat error displayed to user",
      error: error_msg,
      raw_reason: inspect(reason, pretty: true)
    )

    error_msg
  end

  defp conversation_preview(%Conversation{preview: preview}) when is_binary(preview) do
    preview
  end

  defp conversation_preview(_), do: "Ask anything about your clients, inbox, or calendar."

  defp message_alignment_class("user"), do: "items-end"
  defp message_alignment_class(_), do: "items-start"

  defp message_card_class("user"),
    do:
      "ml-auto max-w-[92%] rounded-3xl border border-slate-200 bg-white px-4 py-3 text-slate-900 shadow-md shadow-slate-200/40"

  defp message_card_class("assistant"),
    do:
      "max-w-[92%] rounded-3xl border border-slate-100 bg-slate-50 px-4 py-4 text-slate-900 shadow-sm"

  defp message_card_class("tool"),
    do:
      "max-w-[92%] rounded-3xl border border-blue-100 bg-blue-50 px-4 py-4 text-slate-900 shadow-sm"

  defp message_card_class(_),
    do:
      "max-w-[92%] rounded-3xl border border-slate-100 bg-white px-4 py-4 text-slate-900 shadow-sm"

  defp message_role_label("user"), do: "You asked"
  defp message_role_label("assistant"), do: "Advisor AI"
  defp message_role_label("tool"), do: "Tool"
  defp message_role_label(_), do: "System"

  defp tool_result_summary(%{tool_result: %{} = result}) do
    [
      extract_result_entry(result, [:answer, "answer"], "Answer"),
      extract_result_entry(result, [:summary, "summary"], "Summary"),
      extract_result_entry(result, [:status, "status"], "Status"),
      extract_result_entry(result, [:outcome, "outcome"], "Outcome")
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.take(3)
  end

  defp tool_result_summary(_), do: []

  defp extract_result_entry(result, keys, label) do
    value =
      keys
      |> Enum.reduce_while(nil, fn key, _acc ->
        case fetch_result_value(result, key) do
          nil -> {:cont, nil}
          found -> {:halt, found}
        end
      end)

    cond do
      is_binary(value) and String.trim(value) != "" ->
        %{label: label, value: truncate(value, 160)}

      true ->
        nil
    end
  end

  defp fetch_result_value(result, key) when is_atom(key) do
    Map.get(result, key)
  end

  defp fetch_result_value(result, key) when is_binary(key) do
    Map.get(result, key) ||
      Map.get(result, String.to_atom(key))
  rescue
    ArgumentError ->
      Map.get(result, key)
  end

  defp citations_for(%{tool_result: %{} = result}) do
    result
    |> fetch_result_value("citations")
    |> normalize_citations()
  end

  defp citations_for(_), do: []

  defp normalize_citations(list) when is_list(list) do
    list
    |> Enum.map(&normalize_citation/1)
    |> Enum.reject(&is_nil/1)
  end

  defp normalize_citations(_), do: []

  defp normalize_citation(citation) when is_binary(citation) do
    label = String.trim(citation)

    if label == "" do
      nil
    else
      %{label: truncate(label, 80)}
    end
  end

  defp normalize_citation(%{} = citation) do
    label =
      [
        Map.get(citation, "label"),
        Map.get(citation, :label),
        Map.get(citation, "title"),
        Map.get(citation, :title),
        Map.get(citation, "subject"),
        Map.get(citation, :subject),
        Map.get(citation, "person_name"),
        Map.get(citation, :person_name)
      ]
      |> Enum.find(fn value -> is_binary(value) and String.trim(value) != "" end)

    detail =
      [
        Map.get(citation, "date"),
        Map.get(citation, :date),
        Map.get(citation, "snippet"),
        Map.get(citation, :snippet)
      ]
      |> Enum.find(fn value -> is_binary(value) and String.trim(value) != "" end)

    cond do
      is_nil(label) and is_nil(detail) ->
        nil

      true ->
        %{
          label: truncate(label || detail, 80),
          detail: if(detail && label && detail != label, do: truncate(detail, 120), else: nil)
        }
    end
  end

  defp normalize_citation(_), do: nil

  defp truncate(nil, _max), do: nil

  defp truncate(text, max) when is_binary(text) and max > 0 do
    text = String.trim(text)

    if String.length(text) <= max do
      text
    else
      String.slice(text, 0, max) <> "..."
    end
  end

  defp truncate(text, _max) when is_binary(text), do: String.trim(text)

  defp tab_button_class(active_tab, tab) do
    base =
      "flex items-center gap-2 rounded-full px-4 py-2 text-sm font-semibold transition focus:outline-none focus:ring-2 focus:ring-blue-300"

    if active_tab == tab do
      base <> " bg-blue-50 text-blue-700 ring-1 ring-blue-100"
    else
      base <> " text-slate-500 hover:text-slate-800"
    end
  end

  defp context_chip_class(active_context, %{value: value}) do
    if active_context.value == value do
      [
        "inline-flex items-center gap-2 rounded-full border border-blue-200 bg-blue-50 px-3 py-1 text-xs font-semibold text-blue-700"
      ]
    else
      [
        "inline-flex items-center gap-2 rounded-full border border-slate-200 bg-white px-3 py-1 text-xs font-semibold text-slate-500 hover:border-slate-300 hover:text-slate-700"
      ]
    end
  end

  defp context_description(%{label: label}), do: "Context set to #{String.downcase(label)}"

  defp context_timestamp(nil) do
    now = DateTime.utc_now()
    format_time(now) <> " — " <> Calendar.strftime(now, "%b %-d, %Y")
  end

  defp context_timestamp(%Conversation{last_message_at: nil}) do
    now = DateTime.utc_now()
    format_time(now) <> " — " <> Calendar.strftime(now, "%b %-d, %Y")
  end

  defp context_timestamp(%Conversation{last_message_at: naive}) do
    time = format_time(naive)
    date = Calendar.strftime(naive, "%b %-d, %Y")
    time <> " — " <> date
  end

  defp format_time(%NaiveDateTime{} = naive) do
    Calendar.strftime(naive, "%-I:%M%p")
    |> String.replace("AM", "am")
    |> String.replace("PM", "pm")
  end

  defp format_time(%DateTime{} = dt) do
    Calendar.strftime(dt, "%-I:%M%p") |> String.replace("AM", "am") |> String.replace("PM", "pm")
  end

  defp composer_placeholder(%{label: label}),
    do: "Ask anything about your #{String.downcase(label)}..."
end
