defmodule Jump.Calendar.FreeBusy do
  @moduledoc """
  Handles free/busy queries and availability analysis for calendar scheduling.
  """

  alias Jump.Calendar.Client
  alias Timex.Timezone
  require Logger

  @default_business_hours_start "09:00"
  @default_business_hours_end "17:00"
  @default_buffer_minutes 15
  @default_min_slot_duration 15

  @doc """
  Get free/busy information for a user within a date range.
  """
  def get_free_busy(user_id, start_date, end_date, opts \\ []) do
    timezone = Keyword.get(opts, :timezone, "UTC")
    calendar_ids = Keyword.get(opts, :calendar_ids, ["primary"])

    with {:ok, conn} <- Client.get_conn(user_id),
         {:ok, response} <-
           Client.get_free_busy(conn, user_id, start_date, end_date, calendar_ids, opts) do
      {:ok, parse_free_busy_response(response, timezone)}
    else
      error -> error
    end
  end

  @doc """
  Analyze availability and return available time slots.
  """
  def analyze_availability(user_id, start_date, end_date, opts \\ []) do
    timezone = Keyword.get(opts, :timezone, "UTC")
    duration_minutes = Keyword.get(opts, :duration_minutes, 30)

    business_hours =
      Keyword.get(opts, :business_hours, %{
        start: @default_business_hours_start,
        end: @default_business_hours_end
      })

    buffer_minutes = Keyword.get(opts, :buffer_minutes, @default_buffer_minutes)
    exclude_weekends = Keyword.get(opts, :exclude_weekends, true)

    with {:ok, free_busy_data} <- get_free_busy(user_id, start_date, end_date, timezone: timezone) do
      busy_blocks = extract_busy_blocks(free_busy_data)

      time_slots =
        find_available_slots(start_date, end_date, duration_minutes, busy_blocks, %{
          timezone: timezone,
          business_hours: business_hours,
          buffer_minutes: buffer_minutes,
          exclude_weekends: exclude_weekends
        })

      {:ok, time_slots}
    else
      error -> error
    end
  end

  @doc """
  Generate meeting proposals for a given date range.
  """
  def generate_meeting_proposals(user_id, start_date, end_date, opts \\ []) do
    timezone = Keyword.get(opts, :timezone, "UTC")
    duration_minutes = Keyword.get(opts, :duration_minutes, 30)
    min_slots = Keyword.get(opts, :min_slots, 3)
    max_slots = Keyword.get(opts, :max_slots, 5)
    preferred_times = Keyword.get(opts, :preferred_times, [])
    max_proposals_per_day = Keyword.get(opts, :max_proposals_per_day, 2)

    with {:ok, available_slots} <-
           analyze_availability(user_id, start_date, end_date,
             timezone: timezone,
             duration_minutes: duration_minutes
           ) do
      proposals =
        select_best_proposals(available_slots, %{
          timezone: timezone,
          preferred_times: preferred_times,
          max_proposals_per_day: max_proposals_per_day,
          min_slots: min_slots,
          max_slots: max_slots
        })

      {:ok, proposals}
    else
      error -> error
    end
  end

  @doc """
  Check if a specific time slot is available.
  """
  def is_time_available?(user_id, start_time, end_time, opts \\ []) do
    timezone = Keyword.get(opts, :timezone, "UTC")

    with {:ok, free_busy_data} <- get_free_busy(user_id, start_time, end_time, timezone: timezone) do
      busy_blocks = extract_busy_blocks(free_busy_data)

      # Check if the requested slot overlaps with any busy blocks
      !overlaps_with_busy_blocks?(start_time, end_time, busy_blocks)
    else
      _ -> false
    end
  end

  @doc """
  Find the next available time slot after a given datetime.
  """
  def find_next_available(user_id, after_time, duration_minutes, opts \\ []) do
    timezone = Keyword.get(opts, :timezone, "UTC")
    search_days = Keyword.get(opts, :search_days, 7)

    # Search within the next N days
    end_time = Timex.shift(after_time, days: search_days)

    with {:ok, available_slots} <-
           analyze_availability(user_id, after_time, end_time,
             timezone: timezone,
             duration_minutes: duration_minutes
           ) do
      case Enum.find(available_slots, fn slot ->
             Timex.compare(slot.start_time, after_time) != :lt
           end) do
        nil -> {:error, :no_available_slots}
        slot -> {:ok, slot}
      end
    else
      error -> error
    end
  end

  # Private functions

  defp parse_free_busy_response(response, timezone) do
    calendars = Map.get(response, :calendars, %{})

    busy_blocks =
      calendars
      |> Enum.flat_map(fn {calendar_id, calendar_data} ->
        parse_calendar_busy_blocks(calendar_data, calendar_id, timezone)
      end)
      |> Enum.sort_by(&DateTime.to_unix(&1.start))

    %{
      time_min: response.time_min,
      time_max: response.time_max,
      busy_blocks: busy_blocks,
      timezone: timezone
    }
  end

  defp parse_calendar_busy_blocks(%{"busy" => busy_blocks}, calendar_id, timezone) do
    Enum.map(busy_blocks, fn block ->
      %{
        calendar_id: calendar_id,
        start: parse_datetime(block["start"], timezone),
        end: parse_datetime(block["end"], timezone)
      }
    end)
  end

  defp parse_calendar_busy_blocks(_, _calendar_id, _timezone), do: []

  defp parse_datetime(datetime_str, timezone) do
    case DateTime.from_iso8601(datetime_str) do
      {:ok, dt, _} ->
        dt

      {:error, _} ->
        # Try to parse as date only
        case Date.from_iso8601(datetime_str) do
          {:ok, date} ->
            {:ok, dt} = Timezone.convert(DateTime.new!(date, ~T[00:00:00]), timezone)
            dt

          {:error, _} ->
            Logger.error("Failed to parse datetime: #{datetime_str}")
            DateTime.utc_now()
        end
    end
  end

  defp extract_busy_blocks(free_busy_data) do
    Map.get(free_busy_data, :busy_blocks, [])
  end

  defp find_available_slots(start_date, end_date, duration_minutes, busy_blocks, options) do
    timezone = options.timezone
    business_hours = options.business_hours
    buffer_minutes = options.buffer_minutes
    exclude_weekends = options.exclude_weekends

    # Convert dates to datetime objects in the target timezone
    {:ok, start_dt} = Timezone.convert(DateTime.new!(start_date, ~T[00:00:00]), timezone)
    {:ok, end_dt} = Timezone.convert(DateTime.new!(end_date, ~T[23:59:59]), timezone)

    # Generate day-by-day schedule
    days = generate_days_range(start_dt, end_dt, timezone, exclude_weekends)

    # Find available slots for each day
    available_slots =
      Enum.flat_map(days, fn day ->
        find_daily_available_slots(day, duration_minutes, busy_blocks, %{
          timezone: timezone,
          business_hours: business_hours,
          buffer_minutes: buffer_minutes
        })
      end)

    available_slots
    |> Enum.sort_by(&DateTime.to_unix(&1.start_time))
    # Limit to reasonable number of slots
    |> Enum.take(20)
  end

  defp generate_days_range(start_dt, end_dt, timezone, exclude_weekends) do
    Timex.Interval.new(from: start_dt, until: end_dt, step: [days: 1])
    |> Timex.Interval.with_step(&Timex.shift(&1, days: 1))
    |> Enum.filter(fn dt ->
      if exclude_weekends do
        day_of_week = Date.day_of_week(dt)
        # Saturday and Sunday
        day_of_week != 6 and day_of_week != 7
      else
        true
      end
    end)
    |> Enum.map(fn dt ->
      {:ok, converted} = Timezone.convert(dt, timezone)
      converted
    end)
  end

  defp find_daily_available_slots(day, duration_minutes, busy_blocks, options) do
    timezone = options.timezone
    business_hours = options.business_hours
    buffer_minutes = options.buffer_minutes

    # Parse business hours
    {start_hour, start_min} = parse_time_string(business_hours.start)
    {end_hour, end_min} = parse_time_string(business_hours.end)

    # Create business hours window for the day
    business_start = DateTime.new!(day, Time.new!(start_hour, start_min, 0))
    business_end = DateTime.new!(day, Time.new!(end_hour, end_min, 0))

    # Convert to target timezone
    {:ok, business_start} = Timezone.convert(business_start, timezone)
    {:ok, business_end} = Timezone.convert(business_end, timezone)

    # Filter busy blocks for this day
    daily_busy =
      Enum.filter(busy_blocks, fn busy ->
        busy.start >= business_start and busy.start < business_end
      end)

    # Find gaps between busy blocks
    find_gaps_in_schedule(
      business_start,
      business_end,
      daily_busy,
      duration_minutes,
      buffer_minutes
    )
  end

  defp parse_time_string(time_str) do
    case String.split(time_str, ":") do
      [hour, minute] -> {String.to_integer(hour), String.to_integer(minute)}
      [hour] -> {String.to_integer(hour), 0}
      # Default to 9:00 AM
      _ -> {9, 0}
    end
  end

  defp find_gaps_in_schedule(
         business_start,
         business_end,
         busy_blocks,
         duration_minutes,
         buffer_minutes
       ) do
    # Sort busy blocks by start time
    sorted_busy = Enum.sort_by(busy_blocks, &DateTime.to_unix(&1.start))

    # Add buffer minutes to duration
    required_duration = duration_minutes + buffer_minutes

    # Find gaps
    gaps = find_gaps_between_blocks(business_start, business_end, sorted_busy, required_duration)

    # Convert gaps to slot structs
    Enum.map(gaps, fn {gap_start, gap_end} ->
      %{
        start_time: gap_start,
        end_time: gap_end,
        duration_minutes: round(DateTime.diff(gap_end, gap_start) / 60),
        confidence: calculate_confidence(gap_start, gap_end, sorted_busy)
      }
    end)
  end

  defp find_gaps_between_blocks(business_start, business_end, busy_blocks, required_minutes) do
    case busy_blocks do
      [] ->
        # No busy blocks, the entire business day is available
        if duration_sufficient?(business_start, business_end, required_minutes) do
          [{business_start, business_end}]
        else
          []
        end

      [first_busy | rest] ->
        gaps = []

        # Gap before first busy block
        gaps =
          if duration_sufficient?(business_start, first_busy.start, required_minutes) do
            [{business_start, first_busy.start} | gaps]
          else
            gaps
          end

        # Gaps between busy blocks
        gaps =
          Enum.reduce(rest, gaps, fn busy_block, acc ->
            previous_busy =
              List.first(
                Enum.filter(busy_blocks, &(DateTime.compare(&1.start, busy_block.start) == :lt))
              )

            if previous_busy &&
                 duration_sufficient?(previous_busy.end, busy_block.start, required_minutes) do
              [{previous_busy.end, busy_block.start} | acc]
            else
              acc
            end
          end)

        # Gap after last busy block
        last_busy = List.last(busy_blocks)

        gaps =
          if duration_sufficient?(last_busy.end, business_end, required_minutes) do
            [{last_busy.end, business_end} | gaps]
          else
            gaps
          end

        gaps
    end
  end

  defp duration_sufficient?(start_time, end_time, required_minutes) do
    duration_minutes = DateTime.diff(end_time, start_time) / 60
    duration_minutes >= required_minutes
  end

  defp calculate_confidence(start_time, end_time, busy_blocks) do
    # Base confidence depends on how far in the future the slot is
    hours_from_now = DateTime.diff(start_time, DateTime.utc_now()) / 3600

    base_confidence =
      cond do
        # Very near future - more likely to be taken
        hours_from_now < 1 -> 0.5
        hours_from_now < 24 -> 0.8
        hours_from_now < 72 -> 0.9
        true -> 0.95
      end

    # Adjust confidence based on proximity to busy blocks
    proximity_factor = calculate_proximity_factor(start_time, end_time, busy_blocks)

    base_confidence * proximity_factor
  end

  defp calculate_proximity_factor(start_time, end_time, busy_blocks) do
    case find_nearest_busy_block(start_time, end_time, busy_blocks) do
      nil ->
        1.0

      {distance_minutes, _busy_block} ->
        # Reduce confidence if slot is very close to busy times
        cond do
          distance_minutes < 15 -> 0.7
          distance_minutes < 30 -> 0.85
          true -> 1.0
        end
    end
  end

  defp find_nearest_busy_block(start_time, end_time, busy_blocks) do
    Enum.reduce(busy_blocks, nil, fn busy_block, nearest ->
      distance_start = abs(DateTime.diff(busy_block.start, start_time, :minute))
      distance_end = abs(DateTime.diff(busy_block.end, end_time, :minute))
      min_distance = min(distance_start, distance_end)

      case nearest do
        nil -> {min_distance, busy_block}
        {nearest_distance, _} when min_distance < nearest_distance -> {min_distance, busy_block}
        _ -> nearest
      end
    end)
  end

  defp overlaps_with_busy_blocks?(start_time, end_time, busy_blocks) do
    Enum.any?(busy_blocks, fn busy ->
      # Check if intervals overlap
      not (DateTime.compare(end_time, busy.start) != :gt or
             DateTime.compare(start_time, busy.end) != :lt)
    end)
  end

  defp select_best_proposals(available_slots, options) do
    timezone = options.timezone
    preferred_times = options.preferred_times
    max_proposals_per_day = options.max_proposals_per_day
    min_slots = options.min_slots
    max_slots = options.max_slots

    # Score and sort slots
    scored_slots =
      available_slots
      |> Enum.map(fn slot ->
        score = score_slot(slot, preferred_times, timezone)
        Map.put(slot, :score, score)
      end)
      # Sort by descending score
      |> Enum.sort_by(&(-&1.score))

    # Group by date and select best slots per day
    grouped_by_date =
      scored_slots
      |> Enum.group_by(fn slot -> DateTime.to_date(slot.start_time) end)

    # Select top slots per day
    proposals =
      Enum.flat_map(grouped_by_date, fn {_date, daily_slots} ->
        daily_slots
        |> Enum.take(max_proposals_per_day)
      end)
      |> Enum.sort_by(&(-&1.score))
      |> Enum.take(max_slots)

    # Ensure we have at least min_slots
    if length(proposals) < min_slots do
      # If we don't have enough preferred slots, add more from the available ones
      additional =
        scored_slots
        |> Enum.filter(fn slot ->
          not Enum.any?(proposals, fn prop -> prop.start_time == slot.start_time end)
        end)
        |> Enum.take(min_slots - length(proposals))

      proposals ++ additional
    else
      proposals
    end
  end

  defp score_slot(slot, preferred_times, timezone) do
    # Base score from confidence
    base_score = Map.get(slot, :confidence, 0.8) * 100

    # Time of day preference
    time_score = calculate_time_preference_score(slot.start_time, preferred_times, timezone)

    # Day of week preference (weekdays preferred)
    day_score = calculate_day_preference_score(slot.start_time)

    # Distance from now (prefer reasonable future times)
    distance_score = calculate_distance_preference_score(slot.start_time)

    base_score + time_score + day_score + distance_score
  end

  defp calculate_time_preference_score(datetime, preferred_times, timezone) do
    if Enum.empty?(preferred_times) do
      # Default: prefer mid-morning and mid-afternoon
      hour = datetime.hour

      cond do
        hour >= 9 and hour < 11 -> 20
        hour >= 14 and hour < 16 -> 15
        hour >= 11 and hour < 14 -> 10
        hour >= 16 and hour < 18 -> 5
        true -> 0
      end
    else
      # Score based on preferred times
      Enum.reduce(preferred_times, 0, fn preferred_time, acc ->
        if is_within_preferred_time?(datetime, preferred_time, timezone) do
          acc + 25
        else
          acc
        end
      end)
    end
  end

  defp is_within_preferred_time?(datetime, preferred_time, timezone) do
    # Parse preferred_time like "morning", "afternoon", or "14:00-16:00"
    case preferred_time do
      "morning" ->
        datetime.hour >= 9 and datetime.hour < 12

      "afternoon" ->
        datetime.hour >= 12 and datetime.hour < 17

      "evening" ->
        datetime.hour >= 17 and datetime.hour < 20

      time_range when is_binary(time_range) ->
        case String.split(time_range, "-") do
          [start_str, end_str] ->
            {start_hour, _} = parse_time_string(start_str)
            {end_hour, _} = parse_time_string(end_str)
            datetime.hour >= start_hour and datetime.hour < end_hour

          _ ->
            false
        end

      _ ->
        false
    end
  end

  defp calculate_day_preference_score(datetime) do
    day_of_week = Date.day_of_week(datetime)

    cond do
      # Tuesday-Friday (best)
      day_of_week >= 2 and day_of_week <= 5 -> 15
      # Monday, Saturday
      day_of_week == 1 or day_of_week == 6 -> 10
      # Sunday
      day_of_week == 7 -> 0
      true -> 5
    end
  end

  defp calculate_distance_preference_score(datetime) do
    hours_from_now = DateTime.diff(datetime, DateTime.utc_now(), :hour)

    cond do
      # Too soon
      hours_from_now < 1 -> -10
      # Tomorrow
      hours_from_now < 24 -> 15
      # Next few days
      hours_from_now < 72 -> 20
      # Next week
      hours_from_now < 168 -> 10
      # Too far
      true -> 0
    end
  end
end
