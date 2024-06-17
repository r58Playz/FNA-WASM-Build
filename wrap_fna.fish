set FUNCS "void FNA3D_SwapBuffers(FNA3D_Device *device, FNA3D_Rect *sourceRectangle, FNA3D_Rect *destinationRectangle, void *overrideWindowHandle)"

echo "#include \"FNA/lib/FNA3D/include/FNA3D.h\""
echo "#include <emscripten/proxying.h>"
echo "#include <emscripten/threading.h>"
echo "#include <assert.h>"

for func in $FUNCS
	set ret $(string split ' ' -f 1 $func)
	set name $(string split '(' -f 1 $func | string split ' ' -f 2)
	set args $(string split '(' -f 2 $func | sed 's/)//')
	set argsargs $(echo -n $args | sed -e 's/[a-zA-Z0-9_]* \**//g')
	set argc $(echo $argsargs | sed 's/[^,]//g' | string length)
	set argc $(math $argc + 1)

	echo typedef struct \{
	for arg in $(string split ',' $args)
		echo \t$(string trim $arg)\;
	end
	echo \t$ret \*WRAP_RET\;
	echo \} WRAP__struct_$name\;

	echo void WRAP__MAIN__$name\(void \*wrap_struct_ptr\) \{
	echo \tWRAP__struct_$name \*wrap_struct \= \(WRAP__struct_$name\*\)wrap_struct_ptr\;
	echo \t\*\(wrap_struct\-\>WRAP_RET\) \= $name\(
	set i 0
	for arg in $(string split ',' $argsargs)
		set argtrimmed $(string trim $arg)
		echo -n \t\twrap_struct\-\>$argtrimmed
		if test $i -eq $(math $argc - 1)
			echo
		else
			echo \,
		end
		set i $(math $i + 1)
	end
	echo \t\)\;
	echo \}

	echo $ret WRAP_$name\($args\)
	echo \{
	echo \t\/\/ \$func: `$func`
	echo \t\/\/ \$ret: `$ret`
	echo \t\/\/ \$name: `$name`
	echo \t\/\/ \$args: `$args`
	echo \t\/\/ \$argsargs: `$argsargs`
	echo \t\/\/ \$argc: `$argc`
	echo \t\/\/
	echo \t\/\/ return $name\($argsargs\)\;
	echo \t$ret wrap_ret \= 0\;
	echo \tWRAP__struct_$name wrap_struct \= \{
	for arg in $(string split ',' $argsargs)
		set argtrimmed $(string trim $arg)
		echo \t\t.$argtrimmed \= $argtrimmed\,
	end
	echo \t\t.WRAP_RET \= \&wrap_ret
	echo \t\}\;
	echo \tif \(\!emscripten_proxy_sync\(emscripten_proxy_get_system_queue\(\), emscripten_main_runtime_thread_id\(\), WRAP__MAIN__$name, \(void\*\)\&wrap_struct\)\) \{
	echo \t\temscripten_run_script\(\"console.error\(\'wrap.fish: failed to proxy $name\'\)\"\)\;
	echo \t\tassert\(0\)\;
	echo \t\}
	echo \treturn wrap_ret\;
	echo \}
	echo
end
