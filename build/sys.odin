package build

import "core:c/libc"
import "core:fmt"
import "core:os"
import "core:strings"

sys_run :: proc(cmd: string) -> bool {
	fmt.println(">", cmd)
	return libc.system(strings.clone_to_cstring(cmd)) == 0
}

sys_make_dir :: proc(path: string) -> bool {
	if os.exists(path) do return true
	os.make_directory(path, 0o755)
	return os.exists(path)
}

sys_copy :: proc(src, dst: string) -> (ok: bool) {
	f_src, err_src := os.open(src, os.O_RDONLY)
	if err_src != 0 do return false
	defer os.close(f_src)

	f_dst, err_dst := os.open(dst, os.O_WRONLY | os.O_CREATE | os.O_TRUNC, 0o644)
	if err_dst != 0 do return false
	defer os.close(f_dst)

	buf: [4096]byte
	for {
		read_bytes, err_read := os.read(f_src, buf[:])
		if read_bytes == 0 || err_read != 0 do break

		_, err_write := os.write(f_dst, buf[:read_bytes])
		if err_write != 0 do return false
	}

	return true
}

sys_copy_dir :: proc(src_dir, dst_dir: string) -> bool {
	dir_fd, err_dir := os.open(src_dir, os.O_RDONLY)
	if err_dir != 0 {
		fmt.eprintf("Error: could not open directory %s\n", src_dir)
		return false
	}
	defer os.close(dir_fd)

	entries, err_read := os.read_dir(dir_fd, -1)
	if err_read != 0 {
		fmt.eprintf("Error: could not read directory %s\n", src_dir)
		return false
	}
	defer os.file_info_slice_delete(entries)

	all_ok := true
	for entry in entries {
		src_path := fmt.tprintf("%s/%s", src_dir, entry.name)
		dst_path := fmt.tprintf("%s/%s", dst_dir, entry.name)
		if entry.is_dir {
			sys_make_dir(dst_path)
			if !sys_copy_dir(src_path, dst_path) do all_ok = false
		} else {
			if !sys_copy(src_path, dst_path) {
				fmt.eprintf("Warning: failed to copy %s\n", src_path)
				all_ok = false
			}
		}
	}
	return all_ok
}

sys_download :: proc(url, output: string) -> bool {
	if os.exists(output) {
		fmt.printf("Already exists: %s — skipping download\n", output)
		return true
	}
	return sys_run(strings.concatenate({"curl -L -o ", output, " \"", url, "\""}))
}
