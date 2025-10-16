defmodule Jump.Calendar.Proposals do
  @moduledoc """
  Generates and manages meeting proposals with smart scheduling logic.
  """

  alias Jump.Calendar.FreeBusy
  alias Timex.Timezone
  require Logger

  @default_proposal_duration 30
  @default_buffer_minutes 15
  @max_proposals_per_request 10

  @doc """
  Generate meeting proposals for scheduling a meeting.
  """
  def generate_proposals(user_id, opts \\ []) do
    # Extract options with defaults
    start_date = Keyword.get(opts, :start_date) || Date.add(Date.utc_today(), 1)
    end_date = Keyword.get(opts, :end_date) || Date.add(start_date, 7)
    duration_minutes = Keyword.get(opts, :duration_minutes, @default_proposal_duration)
    timezone = Keyword.get(opts, :timezone, "UTC")
    min_slots = Keyword.get(opts, :min_slots, 3)
    max_slots = Keyword.get(opts, :max_slots, 5)

    # Additional preferences
    preferred_times = Keyword.get(opts, :preferred_times, [])

    business_hours =
      Keyword.get(opts, :business_hours, %{
        start: "09:00",
        end: "17:00"
      })

    exclude_weekends = Keyword.get(opts, :exclude_weekends, true)
    max_proposals_per_day = Keyword.get(opts, :max_proposals_per_day, 2)

    # Validate inputs
    with :ok <- validate_date_range(start_date, end_date),
         :ok <- validate_duration(duration_minutes) do
      # Generate proposals
      proposal_opts = [
        timezone: timezone,
        duration_minutes: duration_minutes,
        min_slots: min_slots,
        max_slots: min(max_slots, @max_proposals_per_request),
        preferred_times: preferred_times,
        business_hours: business_hours,
        exclude_weekends: exclude_weekends,
        max_proposals_per_day: max_proposals_per_day
      ]

      case FreeBusy.generate_meeting_proposals(user_id, start_date, end_date, proposal_opts) do
        {:ok, proposals} ->
          enriched_proposals = enrich_proposals(proposals, timezone)
          {:ok, enriched_proposals}

        error ->
          error
      end
    else
      error -> error
    end
  end

  @doc """
  Generate proposals for multiple attendees (group scheduling).
  """
  def generate_group_proposals(user_ids, opts \\ []) do
    start_date = Keyword.get(opts, :start_date) || Date.add(Date.utc_today(), 1)
    end_date = Keyword.get(opts, :end_date) || Date.add(start_date, 7)
    duration_minutes = Keyword.get(opts, :duration_minutes, @default_proposal_duration)
    timezone = Keyword.get(opts, :timezone, "UTC")
    min_slots = Keyword.get(opts, :min_slots, 2)
    max_slots = Keyword.get(opts, :max_slots, 4)

    with :ok <- validate_date_range(start_date, end_date),
         :ok <- validate_duration(duration_minutes) do
      # Get availability for all users
      availability_results =
        Enum.map(user_ids, fn user_id ->
          FreeBusy.analyze_availability(user_id, start_date, end_date,
            timezone: timezone,
            duration_minutes: duration_minutes
          )
        end)

      # Check if all users have valid availability
      case Enum.find(availability_results, fn result -> match?({:error, _}, result) end) do
        nil ->
          # All users have availability, find common slots
          user_slots = Enum.map(availability_results, fn {:ok, slots} -> slots end)
          common_slots = find_common_available_slots(user_slots, duration_minutes)

          proposals =
            create_proposals_from_slots(common_slots, %{
              timezone: timezone,
              max_slots: max_slots
            })

          enriched_proposals = enrich_proposals(proposals, timezone)
          {:ok, enriched_proposals}

        {:error, reason} ->
          {:error, reason}
      end
    else
      error -> error
    end
  end

  @doc """
  Create a formatted proposal response for user selection.
  """
  def format_proposal_response(proposals, opts \\ []) do
    timezone = Keyword.get(opts, :timezone, "UTC")
    include_confidence = Keyword.get(opts, :include_confidence, true)

    proposals
    |> Enum.with_index(1)
    |> Enum.map(fn {proposal, index} ->
      format_single_proposal(proposal, index, timezone, include_confidence)
    end)
  end

  @doc """
  Validate a proposal is still available before confirming.
  """
  def validate_proposal_availability(user_id, proposal) do
    start_time = proposal.start_time
    end_time = proposal.end_time

    FreeBusy.is_time_available?(user_id, start_time, end_time)
  end

  @doc """
  Get next available slot as a quick proposal.
  """
  def get_next_available_proposal(user_id, opts \\ []) do
    duration_minutes = Keyword.get(opts, :duration_minutes, @default_proposal_duration)
    timezone = Keyword.get(opts, :timezone, "UTC")
    after_time = Keyword.get(opts, :after_time, DateTime.utc_now())
    search_days = Keyword.get(opts, :search_days, 3)

    case FreeBusy.find_next_available(user_id, after_time, duration_minutes,
           timezone: timezone,
           search_days: search_days
         ) do
      {:ok, slot} ->
        proposal = enrich_proposals([slot], timezone) |> List.first()
        {:ok, proposal}

      error ->
        error
    end
  end

  # Private functions

  defp validate_date_range(start_date, end_date) do
    cond do
      Date.compare(start_date, Date.utc_today()) == :lt ->
        {:error, :start_date_in_past}

      Date.compare(end_date, start_date) == :lt ->
        {:error, :end_date_before_start}

      Date.diff(end_date, start_date) > 30 ->
        {:error, :date_range_too_wide}

      true ->
        :ok
    end
  end

  defp validate_duration(duration_minutes) do
    cond do
      duration_minutes < 15 ->
        {:error, :duration_too_short}

      # 4 hours max
      duration_minutes > 240 ->
        {:error, :duration_too_long}

      true ->
        :ok
    end
  end

  defp enrich_proposals(proposals, timezone) do
    Enum.map(proposals, fn proposal ->
      enriched = %{
        id: generate_proposal_id(),
        start_time: proposal.start_time,
        end_time: proposal.end_time,
        duration_minutes: proposal.duration_minutes,
        timezone: timezone,
        confidence: Map.get(proposal, :confidence, 0.8),
        score: Map.get(proposal, :score, 50)
      }

      # Add formatted times
      enriched
      |> Map.put(:start_formatted, format_datetime_for_display(proposal.start_time, timezone))
      |> Map.put(:end_formatted, format_datetime_for_display(proposal.end_time, timezone))
      |> Map.put(:date_formatted, format_date_for_display(proposal.start_time, timezone))
      |> Map.put(:time_formatted, format_time_for_display(proposal.start_time, timezone))
      |> Map.put(:duration_formatted, format_duration(proposal.duration_minutes))
      |> Map.put(:relative_time, format_relative_time(proposal.start_time))
      |> Map.put(:time_of_day, get_time_of_day(proposal.start_time))
      |> Map.put(:is_today, is_today?(proposal.start_time, timezone))
      |> Map.put(:is_tomorrow, is_tomorrow?(proposal.start_time, timezone))
    end)
  end

  defp find_common_available_slots(user_slots, duration_minutes) do
    # Find intersection of all users' available slots
    case user_slots do
      [] ->
        []

      [first_user_slots | other_users] ->
        Enum.reduce(other_users, first_user_slots, fn user_slot, common ->
          find_slot_intersection(common, user_slot, duration_minutes)
        end)
    end
  end

  defp find_slot_intersection(slots1, slots2, duration_minutes) do
    Enum.reduce(slots1, [], fn slot1, acc ->
      # Find slots in slots2 that overlap with slot1
      overlapping_slots =
        Enum.filter(slots2, fn slot2 ->
          intervals_overlap?(slot1.start_time, slot1.end_time, slot2.start_time, slot2.end_time)
        end)

      # For each overlapping slot, create intersection
      intersections =
        Enum.map(overlapping_slots, fn slot2 ->
          intersection_start =
            max(DateTime.to_unix(slot1.start_time), DateTime.to_unix(slot2.start_time))
            |> DateTime.from_unix!()

          intersection_end =
            min(DateTime.to_unix(slot1.end_time), DateTime.to_unix(slot2.end_time))
            |> DateTime.from_unix!()

          if DateTime.diff(intersection_end, intersection_start) >= duration_minutes * 60 do
            %{
              start_time: intersection_start,
              end_time: intersection_end,
              duration_minutes: round(DateTime.diff(intersection_end, intersection_start) / 60)
            }
          end
        end)

      # Remove nil entries and add to accumulator
      valid_intersections = Enum.filter(intersections, & &1)
      acc ++ valid_intersections
    end)
  end

  defp intervals_overlap?(start1, end1, start2, end2) do
    not (DateTime.compare(end1, start2) != :gt or DateTime.compare(start1, end2) != :lt)
  end

  defp create_proposals_from_slots(slots, opts) do
    max_slots = Keyword.get(opts, :max_slots, 5)

    slots
    |> Enum.sort_by(&DateTime.to_unix(&1.start_time))
    |> Enum.take(max_slots)
    |> Enum.map(fn slot ->
      %{
        start_time: slot.start_time,
        end_time: slot.end_time,
        duration_minutes: slot.duration_minutes,
        # High confidence for common availability
        confidence: 0.9,
        score: 75
      }
    end)
  end

  defp format_single_proposal(proposal, index, timezone, include_confidence) do
    base = """
    #{index}. **#{proposal.date_formatted} at #{proposal.time_formatted}** (#{proposal.duration_formatted})
       #{proposal.relative_time} • #{proposal.time_of_day}
    """

    if include_confidence do
      confidence_percent = round(proposal.confidence * 100)
      base <> " • #{confidence_percent}% confidence"
    else
      base
    end
  end

  defp format_datetime_for_display(datetime, timezone) do
    {:ok, local_dt} = Timezone.convert(datetime, timezone)
    Calendar.strftime(local_dt, "%B %d, %Y at %I:%M %p")
  end

  defp format_date_for_display(datetime, timezone) do
    {:ok, local_dt} = Timezone.convert(datetime, timezone)
    Calendar.strftime(local_dt, "%B %d, %Y")
  end

  defp format_time_for_display(datetime, timezone) do
    {:ok, local_dt} = Timezone.convert(datetime, timezone)
    Calendar.strftime(local_dt, "%I:%M %p")
  end

  defp format_duration(minutes) do
    cond do
      minutes < 60 -> "#{minutes} min"
      minutes == 60 -> "1 hour"
      minutes < 120 -> "1 hour #{rem(minutes, 60)} min"
      true -> "#{div(minutes, 60)} hours"
    end
  end

  defp format_relative_time(datetime) do
    now = DateTime.utc_now()
    days_diff = DateTime.diff(datetime, now, :day)
    hours_diff = DateTime.diff(datetime, now, :hour)

    cond do
      days_diff == 0 -> "Today"
      days_diff == 1 -> "Tomorrow"
      days_diff > 1 and days_diff <= 7 -> "In #{days_diff} days"
      days_diff > 7 -> "In #{div(days_diff, 7)} weeks"
      days_diff < 0 -> "#{abs(days_diff)} days ago"
      true -> "In #{hours_diff} hours"
    end
  end

  defp get_time_of_day(datetime) do
    hour = datetime.hour

    cond do
      hour >= 5 and hour < 12 -> "morning"
      hour >= 12 and hour < 17 -> "afternoon"
      hour >= 17 and hour < 21 -> "evening"
      true -> "night"
    end
  end

  defp is_today?(datetime, timezone) do
    {:ok, local_dt} = Timezone.convert(datetime, timezone)
    {:ok, now_local} = Timezone.convert(DateTime.utc_now(), timezone)
    Date.compare(DateTime.to_date(local_dt), DateTime.to_date(now_local)) == :eq
  end

  defp is_tomorrow?(datetime, timezone) do
    {:ok, local_dt} = Timezone.convert(datetime, timezone)
    {:ok, now_local} = Timezone.convert(DateTime.utc_now(), timezone)
    Date.compare(DateTime.to_date(local_dt), Date.add(DateTime.to_date(now_local), 1)) == :eq
  end

  defp generate_proposal_id do
    "prop_#{:crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)}"
  end
end
