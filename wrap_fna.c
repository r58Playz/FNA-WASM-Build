#include "FNA3D/include/FNA3D.h"
#include <emscripten/proxying.h>
#include <emscripten/threading.h>
#include <assert.h>
typedef struct {
	FNA3D_Device *device;
	FNA3D_Rect *sourceRectangle;
	FNA3D_Rect *destinationRectangle;
	void *overrideWindowHandle;
	void *WRAP_RET;
} WRAP__struct_FNA3D_SwapBuffers;
void WRAP__MAIN__FNA3D_SwapBuffers(void *wrap_struct_ptr) {
	WRAP__struct_FNA3D_SwapBuffers *wrap_struct = (WRAP__struct_FNA3D_SwapBuffers*)wrap_struct_ptr;
	*(wrap_struct->WRAP_RET) = FNA3D_SwapBuffers(
		wrap_struct->device,
		wrap_struct->sourceRectangle,
		wrap_struct->destinationRectangle,
		wrap_struct->overrideWindowHandle
	);
}
void WRAP_FNA3D_SwapBuffers(FNA3D_Device *device, FNA3D_Rect *sourceRectangle, FNA3D_Rect *destinationRectangle, void *overrideWindowHandle)
{
	// $func: `void FNA3D_SwapBuffers(FNA3D_Device *device, FNA3D_Rect *sourceRectangle, FNA3D_Rect *destinationRectangle, void *overrideWindowHandle)`
	// $ret: `void`
	// $name: `FNA3D_SwapBuffers`
	// $args: `FNA3D_Device *device, FNA3D_Rect *sourceRectangle, FNA3D_Rect *destinationRectangle, void *overrideWindowHandle`
	// $argsargs: `device,sourceRectangle,destinationRectangle,overrideWindowHandle`
	// $argc: `4`
	//
	// return FNA3D_SwapBuffers(device,sourceRectangle,destinationRectangle,overrideWindowHandle);
	void wrap_ret = 0;
	WRAP__struct_FNA3D_SwapBuffers wrap_struct = {
		.device = device,
		.sourceRectangle = sourceRectangle,
		.destinationRectangle = destinationRectangle,
		.overrideWindowHandle = overrideWindowHandle,
		.WRAP_RET = &wrap_ret
	};
	if (!emscripten_proxy_sync(emscripten_proxy_get_system_queue(), emscripten_main_runtime_thread_id(), WRAP__MAIN__FNA3D_SwapBuffers, (void*)&wrap_struct)) {
		emscripten_run_script("console.error('wrap.fish: failed to proxy FNA3D_SwapBuffers')");
		assert(0);
	}
	return wrap_ret;
}

