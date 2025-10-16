defmodule Jump.Calendar.Chunker do
  @moduledoc """
  Chunks calendar events for RAG pipeline.
  Converts calendar events into searchable chunks with metadata.
  """

  @doc """
  Create RAG chunks from a calendar event.
  """
  def create_rag_chunks(event, user_id) do
    text = format_event_text(event)

    if String.length(text) > 0 do
      [
        %{
          user_id: user_id,
          source: "calendar",
          source_id: event.id,
          text: text,
          meta: extract_event_metadata(event),
          person_email: get_primary_attendee_email(event),
          person_name: get_primary_attendee_name(event)
        }
      ]
    else
      []
    end
  end

  @doc """
  Create RAG chunks from multiple calendar events.
  """
  def create_rag_chunks_batch(events, user_id) do
    events
    |> Enum.flat_map(&create_rag_chunks(&1, user_id))
  end

  # Private helper functions

  defp format_event_text(event) do
    parts = [
      format_title(event.summary),
      format_datetime(event),
      format_location(event.location),
      format_attendees(event),
      format_description(event.description)
    ]

    parts
    |> Enum.filter(&(&1 && String.length(&1) > 0))
    |> Enum.join("\n\n")
  end

  defp format_title(title) when is_binary(title) and byte_size(title) > 0 do
    "Event: #{title}"
  end

  defp format_title(_), do: nil

  defp format_datetime(event) do
    start_str = format_datetime_value(event.start)
    end_str = format_datetime_value(event.end)

    case {start_str, end_str} do
      {nil, nil} -> nil
      {start, nil} -> "Time: #{start}"
      {nil, end_} -> "Ends: #{end_}"
      {start, end_} -> "Time: #{start} to #{end_}"
    end
  end

  defp format_datetime_value(nil), do: nil

  defp format_datetime_value(%{"dateTime" => date_time_str}) do
    case DateTime.from_iso8601(date_time_str) do
      {:ok, dt, _} -> DateTime.to_string(dt)
      {:error, _} -> date_time_str
    end
  end

  defp format_datetime_value(%{"date" => date_str}) do
    date_str
  end

  defp format_datetime_value(_), do: nil

  defp format_location(location) when is_binary(location) and byte_size(location) > 0 do
    "Location: #{location}"
  end

  defp format_location(_), do: nil

  defp format_attendees(event) do
    attendees = event.attendees || []

    if Enum.empty?(attendees) do
      nil
    else
      attendee_names =
        attendees
        |> Enum.map(&format_attendee/1)
        |> Enum.filter(&(&1 != nil))
        |> Enum.join(", ")

      if String.length(attendee_names) > 0 do
        "Attendees: #{attendee_names}"
      else
        nil
      end
    end
  end

  defp format_attendee(attendee) when is_map(attendee) do
    case attendee do
      %{"displayName" => name} when is_binary(name) -> name
      %{"email" => email} when is_binary(email) -> email
      _ -> nil
    end
  end

  defp format_attendee(_), do: nil

  defp format_description(description)
       when is_binary(description) and byte_size(description) > 0 do
    description
    |> String.slice(0, 1000)
  end

  defp format_description(_), do: nil

  defp extract_event_metadata(event) do
    %{
      event_id: event.id,
      summary: event.summary,
      location: event.location,
      start_time: get_datetime_value(event.start),
      end_time: get_datetime_value(event.end),
      all_day: is_all_day_event(event),
      attendee_count: (event.attendees || []) |> length(),
      organizer: extract_organizer(event.organizer),
      created: event.created,
      updated: event.updated,
      recurring: event.recurringEventId != nil,
      event_type: event.eventType,
      status: event.status,
      html_link: event.htmlLink
    }
  end

  defp get_datetime_value(nil), do: nil
  defp get_datetime_value(%{"dateTime" => dt}), do: dt
  defp get_datetime_value(%{"date" => d}), do: d
  defp get_datetime_value(_), do: nil

  defp is_all_day_event(event) do
    case event.start do
      %{"date" => _} -> true
      _ -> false
    end
  end

  defp extract_organizer(nil), do: nil

  defp extract_organizer(organizer) when is_map(organizer) do
    case organizer do
      %{"displayName" => name, "email" => email} -> %{name: name, email: email}
      %{"email" => email} -> %{email: email}
      %{"displayName" => name} -> %{name: name}
      _ -> nil
    end
  end

  defp extract_organizer(_), do: nil

  defp get_primary_attendee_email(event) do
    case event.organizer do
      %{"email" => email} -> email
      _ -> nil
    end
  end

  defp get_primary_attendee_name(event) do
    case event.organizer do
      %{"displayName" => name} when is_binary(name) -> name
      %{"email" => email} -> email
      _ -> event.summary
    end
  end
end
