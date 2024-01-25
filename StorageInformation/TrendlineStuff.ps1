


class Trendline4
{
    hidden [System.Collections.Generic.List[int64]] $xAxisValues
    hidden [System.Collections.Generic.List[int64]] $yAxisValues
    hidden [int64] $count
    hidden [int64] $xAxisValuesSum
    hidden [int64] $xxSum
    hidden [int64] $xySum
    hidden [int64] $yAxisValuesSum

    [int64] $Slope
    [int64] $Intercept
    [int64] $Start
    [int64] $End

    Trendline4([System.Collections.Generic.List[int64]] $yAxisValues, [System.Collections.Generic.List[int64]] $xAxisValues)
    {
        $this.yAxisValues = $yAxisValues
        $this.xAxisValues = $xAxisValues

        $this.Initialize()
    }


    [void] Initialize()
    {
        $this.count = $this.yAxisValues.Count
        $this.yAxisValuesSum = ($this.yAxisValues | Measure-Object -Sum).Sum
        $this.xAxisValuesSum = ($this.xAxisValues | Measure-Object -Sum).Sum
        $this.xxSum = 0
        $this.xySum = 0

        for ($i = 0; $i -lt $this.count; $i++)
        {
            $this.xySum += ($this.xAxisValues[$i] * $this.yAxisValues[$i])
            $this.xxSum += ($this.xAxisValues[$i] * $this.xAxisValues[$i])
        }

        $this.Slope = $this.CalculateSlope()
        $this.Intercept = $this.CalculateIntercept()
        $this.Start = $this.CalculateStart()
        $this.End = $this.CalculateEnd()
    }

    [int64] CalculateSlope()
    {
        try
        {
            return (($this.count * $this.xySum) - ($this.xAxisValuesSum * $this.yAxisValuesSum)) / (($this.count * $this.xxSum) - ($this.xAxisValuesSum * $this.xAxisValuesSum))
        }
        catch [System.DivideByZeroException]
        {
            return 0
        }
    }

    [int64] CalculateIntercept()
    {
        return ($this.yAxisValuesSum - ($this.Slope * $this.xAxisValuesSum)) / $this.count
    }

    [int64] CalculateStart()
    {
        return ($this.Slope * $this.xAxisValues[0]) + $this.Intercept
    }

    [int64] CalculateEnd()
    {
        return ($this.Slope * $this.xAxisValues[$this.xAxisValues.Count - 1]) + $this.Intercept
    }
}

class Statistics4
{
    static [Trendline4] CalculateLinearRegression([int64[]] $values)
    {
        $yAxisValues = [System.Collections.Generic.List[int64]]::new()
        $xAxisValues = [System.Collections.Generic.List[int64]]::new()

        for ($i = 0; $i -lt $values.Length; $i++)
        {
            $yAxisValues.Add($values[$i])
            $xAxisValues.Add($i + 1)
        }

        return [Trendline4]::new($yAxisValues, $xAxisValues)
    }
}

$dtThen = [DateTime]::Parse("11-18-2022")
$dtFuture = [DateTime]::Parse("3-1-2023")
$dtNow = $dtThen


while($dtNow -le $dtFuture)
{
    $day = ($dtNow - $dtThen).TotalDays

    # Write-Host ("{0}: {1:N0}" -f @($dtNow.ToString("MM-dd-yyyy"), (($tl.Slope * $day) + $tl.Intercept)))
    ($tl.Slope * $day) + $tl.Intercept
    $dtNow = $dtNow.AddDays(1)
}
