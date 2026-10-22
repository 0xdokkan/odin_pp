package render

import "core:math"
import "core:testing"

@(test)
test_expedition_paired_blur_preserves_gaussian_weights_and_energy :: proc(t:^testing.T) {
	for sigma in ([7]f32{.6,.8,1.405,1.6,2.3,3,5}) {
		kernel:=expedition_blur_kernel(sigma)
		recovered:[9]f32;recovered[0]=kernel.center
		total:=kernel.center
		for pair,i in kernel.pairs {
			a:=i*2+1;fraction:=pair.x-f32(a)
			testing.expect(t,fraction>=0 && fraction<=1)
			recovered[a]=pair.y*(1-fraction);recovered[a+1]=pair.y*fraction
			total+=pair.y*2
		}
		testing.expect(t,abs(total-1)<.000001)
		width:=f64(clamp(sigma,.6,3));normalization:=f64(1)
		for i in 1..<9 {normalization+=2*math.exp(-f64(i*i)/(2*width*width))}
		for weight,i in recovered {
			expected:=math.exp(-f64(i*i)/(2*width*width))/normalization
			testing.expect(t,abs(f64(weight)-expected)<.000001)
		}
	}
}

@(private)
blur_test_linear_sample :: proc(signal:[]f32,position:f32)->f32 {
	base:=int(math.floor(position));fraction:=position-f32(base)
	return signal[clamp(base,0,len(signal)-1)]*(1-fraction)+signal[clamp(base+1,0,len(signal)-1)]*fraction
}

@(test)
test_expedition_paired_blur_matches_thin_hdr_lines_and_clamped_boundaries :: proc(t:^testing.T) {
	// Single-pixel HDR highlights, adjacent colour levels and frame edges
	// exercise the cases that a stretched sparse kernel used to duplicate.
	signal:=[?]f32{8,0,0,.1,0,4,1,0,0,0,.2,0,0,7,0,0,0}
	for sigma in ([4]f32{.6,1.405,1.6,3}) {
		kernel:=expedition_blur_kernel(sigma)
		for _,x in signal {
			paired:=signal[x]*kernel.center
			for pair in kernel.pairs {
				paired+=(blur_test_linear_sample(signal[:],f32(x)+pair.x)+blur_test_linear_sample(signal[:],f32(x)-pair.x))*pair.y
			}
			exact,weight:=f64(0),f64(0)
			for i in -8..=8 {
				w:=math.exp(-f64(i*i)/(2*f64(sigma)*f64(sigma)))
				exact+=f64(signal[clamp(x+i,0,len(signal)-1)])*w;weight+=w
			}
			testing.expect(t,abs(f64(paired)-exact/weight)<.00001)
		}
	}
}
