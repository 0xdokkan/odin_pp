package application

import "core:testing"

@(test)
test_expedition_benchmark_percentiles_and_budget_boundary :: proc(t:^testing.T) {
	samples:[100]f64
	for &sample,i in samples {sample=f64(i+1)}
	r:=expedition_benchmark_statistics(samples[:])
	testing.expect_value(t,r.mean,f64(50.5))
	testing.expect_value(t,r.median,f64(50.5))
	testing.expect_value(t,r.p95,f64(95))
	testing.expect_value(t,r.p99,f64(99))
	testing.expect_value(t,r.maximum,f64(100))
	testing.expect_value(t,r.over_budget,84)

	// The budget is strictly greater than 16.67, not rounded to the printed milliseconds.
	boundary:=[2]f64{16.67,16.670001}
	r=expedition_benchmark_statistics(boundary[:])
	testing.expect_value(t,r.over_budget,1)
	testing.expect_value(t,r.p99,boundary[1])
	single:=[1]f64{7}
	r=expedition_benchmark_statistics(single[:])
	testing.expect_value(t,r.mean,f64(7))
	testing.expect_value(t,r.median,f64(7))
	testing.expect_value(t,r.p95,f64(7))
	testing.expect_value(t,r.p99,f64(7))
	testing.expect_value(t,expedition_benchmark_statistics(nil),Expedition_Benchmark_Statistics{})
}

@(test)
test_expedition_benchmark_subset_matches_whole_stage_numbers :: proc(t:^testing.T) {
	for stage in ([6]int{0,25,26,39,40,195}) {
		testing.expect(t,expedition_benchmark_stage_matches(stage,",0,25,26,39,40,195,"))
	}
	for stage in ([6]int{1,2,5,19,95,196}) {
		testing.expect(t,!expedition_benchmark_stage_matches(stage,",0,25,26,39,40,195,"))
	}
	testing.expect(t,expedition_benchmark_stage_matches(195,""))
}
