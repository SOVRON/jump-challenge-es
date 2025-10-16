defmodule Jump.TestHelpers do
  @moduledoc """
  Helper functions for testing across the project.
  """

  @doc """
  Create a fixed datetime for consistent testing (2024-01-15 12:00:00 UTC)
  """
  def fixed_datetime do
    DateTime.new!(~D[2024-01-15], ~T[12:00:00], "Etc/UTC")
  end

  @doc """
  Create a fixed datetime on a specific date
  """
  def fixed_datetime(year, month, day) do
    date = Date.new!(year, month, day)
    DateTime.new!(date, ~T[12:00:00], "Etc/UTC")
  end

  @doc """
  Create a datetime with time components
  """
  def fixed_datetime(year, month, day, hour, minute, second) do
    date = Date.new!(year, month, day)
    time = Time.new!(hour, minute, second)
    DateTime.new!(date, time, "Etc/UTC")
  end

  @doc """
  Create a date for testing
  """
  def fixed_date do
    ~D[2024-01-15]
  end

  @doc """
  Create a date on a specific day of week (for week boundary testing)
  Returns a Monday
  """
  def monday_date do
    ~D[2024-01-15]
  end

  @doc """
  Get Friday of the same week
  """
  def friday_date do
    ~D[2024-01-19]
  end

  @doc """
  Get Sunday of the same week
  """
  def sunday_date do
    ~D[2024-01-21]
  end

  @doc """
  Create a time for testing
  """
  def fixed_time do
    ~T[12:00:00]
  end

  @doc """
  Create a time with minute precision
  """
  def fixed_time(hour, minute) do
    Time.new!(hour, minute, 0)
  end

  @doc """
  Check if two datetimes are approximately equal (within 1 second)
  """
  def assert_datetime_close(dt1, dt2, tolerance_seconds \\ 1) do
    diff = abs(DateTime.diff(dt1, dt2))
    diff <= tolerance_seconds
  end

  @doc """
  Check if a list contains a map with matching fields
  """
  def has_map_with(list, partial_map) do
    Enum.any?(list, fn item ->
      Enum.all?(partial_map, fn {key, value} ->
        Map.get(item, key) == value
      end)
    end)
  end

  @doc """
  Create sample email addresses for testing
  """
  def sample_email, do: "test@example.com"
  def sample_email(n), do: "user#{n}@example.com"

  @doc """
  Create sample user IDs for testing
  """
  def sample_user_id, do: "user_123"
  def sample_user_id(n), do: "user_#{n}"

  @doc """
  Build a sample error response
  """
  def error_response(message, code \\ "unknown_error") do
    {:error, %{"message" => message, "code" => code}}
  end

  @doc """
  Build a sample success response
  """
  def success_response(data) do
    {:ok, data}
  end
end
