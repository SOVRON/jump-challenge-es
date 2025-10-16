defmodule Jump.TimeHelpers do
  @moduledoc """
  Helper functions for date and time operations that don't exist in Elixir's DateTime module.
  """

  @doc """
  Get the beginning of the day for a given datetime.
  """
  def beginning_of_day(datetime) do
    datetime
    |> DateTime.to_date()
    |> DateTime.new!(~T[00:00:00], datetime.time_zone)
  end

  @doc """
  Get the end of the day for a given datetime (23:59:59.999999).
  """
  def end_of_day(datetime) do
    datetime
    |> DateTime.to_date()
    |> DateTime.new!(~T[23:59:59.999999], datetime.time_zone)
  end

  @doc """
  Get the beginning of the week (Monday) for a given datetime.
  """
  def beginning_of_week(datetime) do
    date = DateTime.to_date(datetime)
    day_of_week = Date.day_of_week(date)
    # day_of_week: 1 = Monday, 2 = Tuesday, ..., 7 = Sunday
    days_back = day_of_week - 1
    beginning_date = Date.add(date, -days_back)
    DateTime.new!(beginning_date, ~T[00:00:00], datetime.time_zone)
  end

  @doc """
  Get the end of the week (Sunday) for a given datetime.
  """
  def end_of_week(datetime) do
    date = DateTime.to_date(datetime)
    day_of_week = Date.day_of_week(date)
    # day_of_week: 1 = Monday, 2 = Tuesday, ..., 7 = Sunday
    days_forward = 7 - day_of_week
    ending_date = Date.add(date, days_forward)
    DateTime.new!(ending_date, ~T[23:59:59.999999], datetime.time_zone)
  end

  @doc """
  Get the beginning of the month for a given datetime.
  """
  def beginning_of_month(datetime) do
    date = DateTime.to_date(datetime)
    beginning_date = Date.new!(date.year, date.month, 1)
    DateTime.new!(beginning_date, ~T[00:00:00], datetime.time_zone)
  end

  @doc """
  Get the end of the month for a given datetime.
  """
  def end_of_month(datetime) do
    date = DateTime.to_date(datetime)
    ending_date = Date.new!(date.year, date.month, number_of_days_in_month(date.year, date.month))
    DateTime.new!(ending_date, ~T[23:59:59.999999], datetime.time_zone)
  end

  @doc """
  Get the beginning of the year for a given datetime.
  """
  def beginning_of_year(datetime) do
    date = DateTime.to_date(datetime)
    beginning_date = Date.new!(date.year, 1, 1)
    DateTime.new!(beginning_date, ~T[00:00:00], datetime.time_zone)
  end

  @doc """
  Get the end of the year for a given datetime.
  """
  def end_of_year(datetime) do
    date = DateTime.to_date(datetime)
    ending_date = Date.new!(date.year, 12, 31)
    DateTime.new!(ending_date, ~T[23:59:59.999999], datetime.time_zone)
  end

  @doc """
  Get the number of days in a month.
  """
  def number_of_days_in_month(year, month) do
    case month do
      2 -> if leap_year?(year), do: 29, else: 28
      month when month in [4, 6, 9, 11] -> 30
      _ -> 31
    end
  end

  @doc """
  Check if a year is a leap year.
  """
  def leap_year?(year) do
    (rem(year, 4) == 0 and rem(year, 100) != 0) or rem(year, 400) == 0
  end
end
