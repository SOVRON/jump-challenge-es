defmodule Jump.TimeHelpersTest do
  use ExUnit.Case

  alias Jump.TimeHelpers

  describe "beginning_of_day/1" do
    test "returns start of day (00:00:00)" do
      dt = DateTime.new!(~D[2024-01-15], ~T[14:30:45], "Etc/UTC")
      result = TimeHelpers.beginning_of_day(dt)

      assert result.hour == 0
      assert result.minute == 0
      assert result.second == 0
      assert result.microsecond == {0, 0}
      assert DateTime.to_date(result) == ~D[2024-01-15]
    end

    test "preserves timezone" do
      dt = DateTime.new!(~D[2024-01-15], ~T[14:30:45], "America/New_York")
      result = TimeHelpers.beginning_of_day(dt)

      assert result.time_zone == "America/New_York"
    end

    test "works with different times of day" do
      midnight = DateTime.new!(~D[2024-01-15], ~T[00:00:00], "Etc/UTC")
      noon = DateTime.new!(~D[2024-01-15], ~T[12:00:00], "Etc/UTC")
      evening = DateTime.new!(~D[2024-01-15], ~T[23:59:59], "Etc/UTC")

      assert TimeHelpers.beginning_of_day(midnight).hour == 0
      assert TimeHelpers.beginning_of_day(noon).hour == 0
      assert TimeHelpers.beginning_of_day(evening).hour == 0
    end
  end

  describe "end_of_day/1" do
    test "returns end of day (23:59:59.999999)" do
      dt = DateTime.new!(~D[2024-01-15], ~T[14:30:45], "Etc/UTC")
      result = TimeHelpers.end_of_day(dt)

      assert result.hour == 23
      assert result.minute == 59
      assert result.second == 59
      assert result.microsecond == {999_999, 6}
      assert DateTime.to_date(result) == ~D[2024-01-15]
    end

    test "preserves timezone" do
      dt = DateTime.new!(~D[2024-01-15], ~T[14:30:45], "America/New_York")
      result = TimeHelpers.end_of_day(dt)

      assert result.time_zone == "America/New_York"
    end
  end

  describe "beginning_of_week/1" do
    test "returns Monday 00:00:00 for dates in week" do
      # 2024-01-15 is a Monday
      monday = DateTime.new!(~D[2024-01-15], ~T[10:00:00], "Etc/UTC")
      result = TimeHelpers.beginning_of_week(monday)

      assert DateTime.to_date(result) == ~D[2024-01-15]
      assert result.hour == 0
      assert result.minute == 0
    end

    test "returns Monday for Friday" do
      # 2024-01-19 is a Friday
      friday = DateTime.new!(~D[2024-01-19], ~T[10:00:00], "Etc/UTC")
      result = TimeHelpers.beginning_of_week(friday)

      assert DateTime.to_date(result) == ~D[2024-01-15]
    end

    test "returns Monday for Sunday" do
      # 2024-01-21 is a Sunday
      sunday = DateTime.new!(~D[2024-01-21], ~T[10:00:00], "Etc/UTC")
      result = TimeHelpers.beginning_of_week(sunday)

      assert DateTime.to_date(result) == ~D[2024-01-15]
    end
  end

  describe "end_of_week/1" do
    test "returns Sunday 23:59:59.999999 for dates in week" do
      # 2024-01-15 is a Monday
      monday = DateTime.new!(~D[2024-01-15], ~T[10:00:00], "Etc/UTC")
      result = TimeHelpers.end_of_week(monday)

      assert DateTime.to_date(result) == ~D[2024-01-21]
      assert result.hour == 23
      assert result.minute == 59
      assert result.second == 59
    end

    test "returns Sunday for Friday" do
      friday = DateTime.new!(~D[2024-01-19], ~T[10:00:00], "Etc/UTC")
      result = TimeHelpers.end_of_week(friday)

      assert DateTime.to_date(result) == ~D[2024-01-21]
    end
  end

  describe "beginning_of_month/1" do
    test "returns first day of month 00:00:00" do
      dt = DateTime.new!(~D[2024-01-15], ~T[14:30:45], "Etc/UTC")
      result = TimeHelpers.beginning_of_month(dt)

      assert DateTime.to_date(result) == ~D[2024-01-01]
      assert result.hour == 0
    end

    test "handles different months" do
      jan_dt = DateTime.new!(~D[2024-01-15], ~T[10:00:00], "Etc/UTC")
      feb_dt = DateTime.new!(~D[2024-02-28], ~T[10:00:00], "Etc/UTC")
      dec_dt = DateTime.new!(~D[2024-12-31], ~T[10:00:00], "Etc/UTC")

      assert DateTime.to_date(TimeHelpers.beginning_of_month(jan_dt)) == ~D[2024-01-01]
      assert DateTime.to_date(TimeHelpers.beginning_of_month(feb_dt)) == ~D[2024-02-01]
      assert DateTime.to_date(TimeHelpers.beginning_of_month(dec_dt)) == ~D[2024-12-01]
    end
  end

  describe "end_of_month/1" do
    test "returns last day of month 23:59:59.999999" do
      dt = DateTime.new!(~D[2024-01-15], ~T[14:30:45], "Etc/UTC")
      result = TimeHelpers.end_of_month(dt)

      assert DateTime.to_date(result) == ~D[2024-01-31]
      assert result.hour == 23
      assert result.minute == 59
    end

    test "handles months with different day counts" do
      jan_dt = DateTime.new!(~D[2024-01-15], ~T[10:00:00], "Etc/UTC")
      feb_dt = DateTime.new!(~D[2024-02-15], ~T[10:00:00], "Etc/UTC")
      apr_dt = DateTime.new!(~D[2024-04-15], ~T[10:00:00], "Etc/UTC")

      assert DateTime.to_date(TimeHelpers.end_of_month(jan_dt)) == ~D[2024-01-31]
      assert DateTime.to_date(TimeHelpers.end_of_month(feb_dt)) == ~D[2024-02-29]
      assert DateTime.to_date(TimeHelpers.end_of_month(apr_dt)) == ~D[2024-04-30]
    end
  end

  describe "beginning_of_year/1" do
    test "returns first day of year 00:00:00" do
      dt = DateTime.new!(~D[2024-06-15], ~T[14:30:45], "Etc/UTC")
      result = TimeHelpers.beginning_of_year(dt)

      assert DateTime.to_date(result) == ~D[2024-01-01]
      assert result.hour == 0
    end

    test "works for different years" do
      dt2024 = DateTime.new!(~D[2024-12-31], ~T[10:00:00], "Etc/UTC")
      dt2023 = DateTime.new!(~D[2023-06-15], ~T[10:00:00], "Etc/UTC")

      assert DateTime.to_date(TimeHelpers.beginning_of_year(dt2024)) == ~D[2024-01-01]
      assert DateTime.to_date(TimeHelpers.beginning_of_year(dt2023)) == ~D[2023-01-01]
    end
  end

  describe "end_of_year/1" do
    test "returns last day of year 23:59:59.999999" do
      dt = DateTime.new!(~D[2024-06-15], ~T[14:30:45], "Etc/UTC")
      result = TimeHelpers.end_of_year(dt)

      assert DateTime.to_date(result) == ~D[2024-12-31]
      assert result.hour == 23
      assert result.minute == 59
    end

    test "works for different years" do
      dt2024 = DateTime.new!(~D[2024-01-01], ~T[10:00:00], "Etc/UTC")
      dt2023 = DateTime.new!(~D[2023-06-15], ~T[10:00:00], "Etc/UTC")

      assert DateTime.to_date(TimeHelpers.end_of_year(dt2024)) == ~D[2024-12-31]
      assert DateTime.to_date(TimeHelpers.end_of_year(dt2023)) == ~D[2023-12-31]
    end
  end

  describe "number_of_days_in_month/2" do
    test "returns correct days for 31-day months" do
      assert TimeHelpers.number_of_days_in_month(2024, 1) == 31
      assert TimeHelpers.number_of_days_in_month(2024, 3) == 31
      assert TimeHelpers.number_of_days_in_month(2024, 5) == 31
    end

    test "returns correct days for 30-day months" do
      assert TimeHelpers.number_of_days_in_month(2024, 4) == 30
      assert TimeHelpers.number_of_days_in_month(2024, 6) == 30
      assert TimeHelpers.number_of_days_in_month(2024, 9) == 30
      assert TimeHelpers.number_of_days_in_month(2024, 11) == 30
    end

    test "returns 28 for non-leap February" do
      assert TimeHelpers.number_of_days_in_month(2023, 2) == 28
      assert TimeHelpers.number_of_days_in_month(2021, 2) == 28
    end

    test "returns 29 for leap February" do
      assert TimeHelpers.number_of_days_in_month(2024, 2) == 29
      assert TimeHelpers.number_of_days_in_month(2020, 2) == 29
    end
  end

  describe "leap_year?/1" do
    test "identifies leap years" do
      assert TimeHelpers.leap_year?(2024) == true
      assert TimeHelpers.leap_year?(2020) == true
      assert TimeHelpers.leap_year?(2000) == true
      assert TimeHelpers.leap_year?(1996) == true
    end

    test "identifies non-leap years" do
      assert TimeHelpers.leap_year?(2023) == false
      assert TimeHelpers.leap_year?(2021) == false
      assert TimeHelpers.leap_year?(1900) == false
      assert TimeHelpers.leap_year?(2100) == false
    end

    test "handles century years correctly" do
      # Years divisible by 100 must also be divisible by 400
      assert TimeHelpers.leap_year?(1900) == false
      assert TimeHelpers.leap_year?(2000) == true
      assert TimeHelpers.leap_year?(2100) == false
    end
  end
end
