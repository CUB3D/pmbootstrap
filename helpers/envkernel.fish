#!/usr/bin/env fish
# Copyright 2018 Oliver Smith
# SPDX-License-Identifier: GPL-3.0-or-later

function check_kernel_folder
	test -e "Kbuild"; and return
	echo "ERROR: This folder is not a linux source tree: $PWD"
	return 1
end


function export_pmbootstrap_dir
	# Get pmbootstrap dir based on this script's location
	set script_dir (dirname (status filename))

	# Fail with debug information
	set -gx pmbootstrap_dir (realpath $script_dir/..)
	if not test -e $pmbootstrap_dir/pmbootstrap.py
		echo "ERROR: Failed to get the script's location with your shell."
		echo "Please adjust export_pmbootstrap_dir in envkernel.fish. Debug info:"
		echo "\$script_dir: $script_dir"
		echo "\$pmbootstrap_dir: $pmbootstrap_dir"
		return 1
	end
end


function set_alias_pmbootstrap
	alias pmbootstrap $pmbootstrap_dir/pmbootstrap.py
	if test -e ~/.config/pmbootstrap.cfg
		pmbootstrap work_migrate
	else
		echo "NOTE: First run of pmbootstrap, running 'pmbootstrap init'"
		pmbootstrap init
	end
end


function export_chroot_device_deviceinfo
	set -gx chroot (pmbootstrap config work)"/chroot_native"
	set -gx device (pmbootstrap config device)
	set -gx deviceinfo $pmbootstrap_dir/aports/device/device-$device/deviceinfo
end


function check_device
	test -e $deviceinfo; and return
	echo "ERROR: Please select a valid device in 'pmbootstrap init'"
	return 1
end


function initialize_chroot
	# Don't initialize twice
	set flag $chroot/tmp/envkernel/setup_done
	test -e $flag; and return

	# Install needed packages
	echo "Initializing Alpine chroot (details: 'pmbootstrap log')"
	pmbootstrap -q chroot -- apk -q add \
		abuild \
		bc \
		binutils-$deviceinfo_arch \
		binutils \
		bison \
		flex \
		gcc-$deviceinfo_arch \
		gcc \
		linux-headers \
		libressl-dev \
		make \
		musl-dev \
		ncurses-dev \
		perl; or return 1

	# Create /mnt/linux
	sudo mkdir -p $chroot/mnt/linux

	# Mark as initialized
	mkdir -p $chroot/tmp/envkernel
	touch $flag
end


function mount_kernel_source
	test -e $chroot/mnt/linux/Kbuild; and return
	sudo mount --bind $PWD $chroot/mnt/linux
end


function create_output_folder
	test -d $chroot/mnt/linux/.output; and return
	mkdir -p ".output"
	pmbootstrap -q chroot -- chown -R pmos:pmos "/mnt/linux/.output"
end


# Ported from /usr/share/abuild/functions.sh
function arch_to_hostspec
	switch $argv[1]
	case aarch64
		echo "aarch64-alpine-linux-musl"
	case armel
		echo "armv5-alpine-linux-musleabi"
	case armhf
		echo "armv6-alpine-linux-muslgnueabihf"
	case armv7
		echo "armv7-alpine-linux-musleabihf"
	case ppc
		echo "powerpc-alpine-linux-musl"
	case ppc64
		echo "powerpc64-alpine-linux-musl"
	case ppc64le
		echo "powerpc64le-alpine-linux-musl"
	case s390x
		echo "s390x-alpine-linux-musl"
	case x86
		echo "i586-alpine-linux-musl"
	case x86_64
		echo "x86_64-alpine-linux-musl"
	case '*'
		echo "unknown"
	end
end


function set_alias_make
	# Cross compiler prefix
	set prefix (arch_to_hostspec $deviceinfo_arch)

	# Kernel architecture
	switch $deviceinfo_arch
	case 'aarch64*'
		set arch "arm64"
	case 'arm*'
		set arch "arm"
	end

	# Build make command
	set cmd "echo '*** pmbootstrap envkernel.fish active for $PWD! ***';"
	set cmd "$cmd pmbootstrap -q chroot --"
	set cmd "$cmd ARCH=$arch"
	set cmd "$cmd CROSS_COMPILE=/usr/bin/$prefix-"
	set cmd "$cmd make -C /mnt/linux O=/mnt/linux/.output"
	alias make $cmd
end


function set_alias_pmbroot_kernelroot
	alias pmbroot "cd '$pmbootstrap_dir'"
	alias kernelroot "cd '$PWD'"
end


# More or less from https://github.com/postmarketOS/pmbootstrap/blob/94306b5/pmb/parse/deviceinfo.py#L48-L56
function parse_deviceinfo
	set lines (cat $deviceinfo)
	for line in $lines
		if not string match -q "deviceinfo_*" $line
			continue
		end
		if not string match -q "*=*" $line
			echo "$deviceinfo: No '=' found: $line"
		end
		set split (string split "=" $line)
		set key $split[1]
		set value (string replace -a '"' '' $split[2])
		set -g $key $value
	end
end


# Stop executing once a function fails
if check_kernel_folder
	and export_pmbootstrap_dir
	and set_alias_pmbootstrap
	and export_chroot_device_deviceinfo
	and check_device
	and parse_deviceinfo
	and initialize_chroot
	and mount_kernel_source
	and create_output_folder
	and set_alias_make
	and set_alias_pmbroot_kernelroot

	# Success
	echo "pmbootstrap envkernel.fish activated successfully."
	echo " * kernel source:  $PWD"
	echo " * output folder:  $PWD/.output"
	echo " * architecture:   $arch ($device is $deviceinfo_arch)"
	echo " * aliases: make, kernelroot, pmbootstrap, pmbroot" \
		"(see 'type make' etc.)"
else
	# Failure
	echo "See also: <https://postmarketos.org/troubleshooting>"
end
