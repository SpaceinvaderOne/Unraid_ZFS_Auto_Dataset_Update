#!/bin/bash
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 
# #   Script for watching a dataset and auto updating regular folders converting them to datasets                                         # #
# #   (needs Unraid 6.12 or above)                                                                                                        # # 
# #   by - SpaceInvaderOne                                                                                                                # # 
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 
#set -x

## Please consider this script in beta at the moment.
## new functions
## Auto stop only docker containers whose appdata is not zfs based.
## Auto stop only vms whose vdisk folder is not a dataset
## Add extra datasets to auto update to source_datasets_array
## Normalises German umlauts into ascii
## Various safety and other checks

# ---------------------------------------
# Main Variables
# ---------------------------------------

# real run or dry run
dry_run="no"  # Set to "yes" for a dry run. Change to "no" to run for real

# Paths
# ---------------------------------------

# Process Docker Containers
should_process_containers="no"  # set to "yes" to process and convert appdata. set paths below
source_pool_where_appdata_is="sg1_storage"  #source pool
source_dataset_where_appdata_is="appdata"   #source appdata dataset

# Process Virtual Machines
should_process_vms="no"  # set to "yes" to process and convert vm vdisk folders. set paths below
source_pool_where_vm_domains_are="darkmatter_disks"  # source pool
source_dataset_where_vm_domains_are="domains"        # source domains dataset
vm_forceshutdown_wait="90"                           # how long to wait for vm to shutdown without force stopping it

# Additional User-Defined Datasets
# Add more paths as needed in the format pool/dataset in quotes, for example: "tank/mydata"
source_datasets_array=(
  # ... user-defined paths here ...
)

cleanup="yes"
replace_spaces="no"

# ---------------------------------------
# Advanced Variables - No need to modify
# ---------------------------------------

# Check if container processing is set to "yes". If so, add location to array and create bind mount compare variable.
if [[ "$should_process_containers" =~ ^[Yy]es$ ]]; then
    source_datasets_array+=("${source_pool_where_appdata_is}/${source_dataset_where_appdata_is}")
    source_path_appdata="$source_pool_where_appdata_is/$source_dataset_where_appdata_is"
fi

# Check if VM processing is set to "yes". If so, add location to array and create vdisk compare variable.
if [[ "$should_process_vms" =~ ^[Yy]es$ ]]; then
    source_datasets_array+=("${source_pool_where_vm_domains_are}/${source_dataset_where_vm_domains_are}")
    source_path_vms="$source_pool_where_vm_domains_are/$source_dataset_where_vm_domains_are"
fi

mount_point="/mnt"
stopped_containers=()
stopped_vms=()
converted_folders=()
buffer_zone=11

#--------------------------------
#     FUNCTIONS START HERE      #
#--------------------------------

#-------------------------------------------------------------------------------------------------
# this function finds the real location of union folder  ie unraid /mnt/user
#
find_real_location() {
  local path="$1"

  if [[ ! -e $path ]]; then
    echo "Path not found."
    return 1
  fi

  for disk_path in /mnt/*/; do
    if [[ "$disk_path" != "/mnt/user/" && -e "${disk_path%/}${path#/mnt/user}" ]]; then
      echo "${disk_path%/}${path#/mnt/user}"
      return 0
    fi
  done

  echo "Real location not found."
  return 2
}

#---------------------------
# this function checks if location is an actively mounted ZFS dataset or not
#
is_zfs_dataset() {
  local location="$1"
  
  if zfs list -H -o mounted,mountpoint | grep -q "^yes"$'\t'"$location$"; then
    return 0
  else
    return 1
  fi
}

#-----------------------------------------------------------------------------------------------------------------------------------  #
# this function checks the running containers and sees if bind mounts are folders or datasets and shuts down containers if needed #
stop_docker_containers() {
  if [ "$should_process_containers" = "yes" ]; then
    echo "Checking Docker containers..."
    
    for container in $(docker ps -q); do
      local container_name=$(docker container inspect --format '{{.Name}}' "$container" | cut -c 2-)
      local bindmounts=$(docker inspect --format '{{ range .Mounts }}{{ if eq .Type "bind" }}{{ .Source }}{{printf "\n"}}{{ end }}{{ end }}' $container) 
      
      if [ -z "$bindmounts" ]; then
        echo "Container ${container_name} has no bind mounts so nothing to convert. No need to stop the container."
        continue
      fi
      
      local stop_container=false

      while IFS= read -r bindmount; do
        if [[ "$bindmount" == /mnt/user/* ]]; then
            bindmount=$(find_real_location "$bindmount")
            if [[ $? -ne 0 ]]; then
                echo "Error finding real location for $bindmount in container $container_name."
                continue
            fi
        fi

        # check if bind mount matches source_path_appdata, if not, skip it
        if [[ "$bindmount" != "/mnt/$source_path_appdata"* ]]; then
            continue
        fi

        local immediate_child=$(echo "$bindmount" | sed -n "s|^/mnt/$source_path_appdata/||p" | cut -d "/" -f 1)
        local combined_path="/mnt/$source_path_appdata/$immediate_child"

        is_zfs_dataset "$combined_path"
        if [[ $? -eq 1 ]]; then
          echo "The appdata for container ${container_name} is not a ZFS dataset (it's a folder). Container will be stopped so it can be converted to a dataset."
          stop_container=true
          break
        fi
      done <<< "$bindmounts"  #  send  bindmounts into the loop

      if [ "$stop_container" = true ]; then
        if [ "$dry_run" != "yes" ]; then
          docker stop "$container_name"
        else
          echo "Dry Run: Docker container $container_name would be stopped"
        fi
        stopped_containers+=("$container_name")
      else
        echo "Container ${container_name} is not required to be stopped as it is already a separate dataset."
      fi
    done

    if [ "${#stopped_containers[@]}" -gt 0 ]; then
      echo "The container/containers ${stopped_containers[*]} has/have been stopped during conversion and will be restarted afterwards."
    fi
  fi
}
#----------------------------------------------------------------------------------    
# this function restarts any containers that had to be stopped
#
start_docker_containers() {
  if [ "$should_process_containers" = "yes" ]; then
    for container_name in "${stopped_containers[@]}"; do
      echo "Restarting Docker container $container_name..."
      if [ "$dry_run" != "yes" ]; then
        docker start "$container_name"
      else
        echo "Dry Run: Docker container $container_name would be restarted"
      fi
    done
  fi
}


# ----------------------------------------------------------------------------------    
#this function gets  dataset path from the full vdisk path
#
get_dataset_path() {
    local fullpath="$1"
    # Extract dataset path
    echo "$fullpath" | rev | cut -d'/' -f2- | rev
}

#------------------------------------------    
# this function getsvdisk info from a vm
#
get_vm_disk() {
    local vm_name="$1"
    # Redirecting debug output to stderr
    echo "Fetching disk for VM: $vm_name" >&2

    # Get target (like hdc, hda, etc.)
    local vm_target=$(virsh domblklist "$vm_name" --details | grep disk | awk '{print $3}')

    # Check if target was found
    if [ -n "$vm_target" ]; then
        # Get the disk for the given target
        local vm_disk=$(virsh domblklist "$vm_name" | grep "$vm_target" | awk '{$1=""; print $0}' | sed 's/^[ \t]*//;s/[ \t]*$//')
        # Redirecting debug output to stderr
        echo "Found disk for $vm_name at target $vm_target: $vm_disk" >&2
        echo "$vm_disk"
    else
        # Redirecting error output to stderr
        echo "Disk not found for VM: $vm_name" >&2
        return 1
    fi
}

#-----------------------------------------------------------------------------------------------------------------------------------  
# this function checks the vdisks any running vm. If visks is not inside a dataset it will stop the vm for processing the conversion
stop_virtual_machines() {
  if [ "$should_process_vms" = "yes" ]; then
    echo "Checking running VMs..."
    
    while IFS= read -r vm; do
      if [ -z "$vm" ]; then
        # Skip if VM name is empty
        continue
      fi

      local vm_disk=$(get_vm_disk "$vm")

      # If the disk is not set, skip this vm
      if [ -z "$vm_disk" ]; then
        echo "No disk found for VM $vm. Skipping..."
        continue
      fi
      
      # Check if VM disk is in a folder and matches source_path_vms
      if [[ "$vm_disk" == /mnt/user/* ]]; then
          vm_disk=$(find_real_location "$vm_disk")
          if [[ $? -ne 0 ]]; then
              echo "Error finding real location for $vm_disk in VM $vm."
              continue
          fi
      fi

      # Check if vm_disk matches source_path_vms, if not, skip it
      if [[ "$vm_disk" != "/mnt/$source_path_vms"* ]]; then
          continue
      fi

      local dataset_path=$(get_dataset_path "$vm_disk")
      local immediate_child=$(echo "$dataset_path" | sed -n "s|^/mnt/$source_path_vms/||p" | cut -d "/" -f 1)
      local combined_path="/mnt/$source_path_vms/$immediate_child"

      is_zfs_dataset "$combined_path"
      if [[ $? -eq 1 ]]; then
        echo "The vdisk for VM ${vm} is not a ZFS dataset (it's a folder). VM will be stopped so it can be converted to a dataset."
        
        if [ "$dry_run" != "yes" ]; then
            virsh shutdown "$vm"  
            
      #  waiting loop for the VM to shutdown
      local start_time=$(date +%s)
      while virsh dominfo "$vm" | grep -q 'running'; do
    sleep 5
    local current_time=$(date +%s)
    if (( current_time - start_time >= $vm_forceshutdown_wait )); then
        echo "VM $vm has not shut down after $vm_forceshutdown_wait seconds. Forcing shutdown now."
        virsh destroy "$vm"
        break
    fi
done
        else
            echo "Dry Run: VM $vm would be stopped"
        fi
        stopped_vms+=("$vm")
      else
        echo "VM ${vm} is not required to be stopped as its vdisk is already in its own dataset."
      fi
    done < <(virsh list --name | grep -v '^$')  # filter empty lines

    if [ "${#stopped_vms[@]}" -gt 0 ]; then
      echo "The VM/VMs ${stopped_vms[*]} has/have been stopped during conversion and will be restarted afterwards."
    fi
  fi
}

#----------------------------------------------------------------------------------    
# this function restarts any vms that had to be stopped
#
start_virtual_machines() {
  if [ "$should_process_vms" = "yes" ]; then
    for vm in "${stopped_vms[@]}"; do
      echo "Restarting VM $vm..."
      if [ "$dry_run" != "yes" ]; then
        virsh start "$vm"  
      else
        echo "Dry Run: VM $vm would be restarted"
      fi
    done
  fi
}

#----------------------------------------------------------------------------------    
# this function normalises umlauts into ascii
#
normalize_name() {
  local original_name="$1"
  # Replace German umlauts with ASCII approximations
  local normalized_name=$(echo "$original_name" | 
                          sed 's/ä/ae/g; s/ö/oe/g; s/ü/ue/g; 
                               s/Ä/Ae/g; s/Ö/Oe/g; s/Ü/Ue/g; 
                               s/ß/ss/g')
  echo "$normalized_name"
}

#----------------------------------------------------------------------------------    
# this function creates the new datasets and does the conversion
#
create_datasets() {
  local source_path="$1"
  for entry in "${mount_point}/${source_path}"/*; do
    base_entry=$(basename "$entry")
    if [[ "$base_entry" != *_temp ]]; then
      base_entry_no_spaces=$(if [ "$replace_spaces" = "yes" ]; then echo "$base_entry" | tr ' ' '_'; else echo "$base_entry"; fi)
      normalized_base_entry=$(normalize_name "$base_entry_no_spaces")
      
      if zfs list -o name | grep -qE "^${source_path}/${normalized_base_entry}$"; then
        echo "Skipping dataset ${entry}..."
      elif [ -d "$entry" ]; then
        echo "Processing folder ${entry}..."
        folder_size=$(du -sb "$entry" | cut -f1)  # This is in bytes
        folder_size_hr=$(du -sh "$entry" | cut -f1)  # This is in human readable
        echo "Folder size: $folder_size_hr"
        buffer_zone_size=$((folder_size * buffer_zone / 100))
        
        if zfs list -o name | grep -qE "^${source_path}" && (( $(zfs list -o avail -p -H "${source_path}") >= buffer_zone_size )); then
          echo "Creating and populating new dataset ${source_path}/${normalized_base_entry}..."
          if [ "$dry_run" != "yes" ]; then
            mv "$entry" "${mount_point}/${source_path}/${normalized_base_entry}_temp"
            if zfs create "${source_path}/${normalized_base_entry}"; then
              rsync -a "${mount_point}/${source_path}/${normalized_base_entry}_temp/" "${mount_point}/${source_path}/${normalized_base_entry}/"
              rsync_exit_status=$?
              if [ "$cleanup" = "yes" ] && [ $rsync_exit_status -eq 0 ]; then
                echo "Validating copy..."
                source_file_count=$(find "${mount_point}/${source_path}/${normalized_base_entry}_temp" -type f | wc -l)
                destination_file_count=$(find "${mount_point}/${source_path}/${normalized_base_entry}" -type f | wc -l)
                source_total_size=$(du -sb "${mount_point}/${source_path}/${normalized_base_entry}_temp" | cut -f1)
                destination_total_size=$(du -sb "${mount_point}/${source_path}/${normalized_base_entry}" | cut -f1)
                if [ "$source_file_count" -eq "$destination_file_count" ] && [ "$source_total_size" -eq "$destination_total_size" ]; then
                  echo "Validation successful, cleanup can proceed."
                  rm -r "${mount_point}/${source_path}/${normalized_base_entry}_temp"
                  converted_folders+=("$entry")  # Save the name of the converted folder
                else
                  echo "Validation failed. Source and destination file count or total size do not match."
                  echo "Source files: $source_file_count, Destination files: $destination_file_count"
                  echo "Source total size: $source_total_size, Destination total size: $destination_total_size"
                fi
              elif [ "$cleanup" = "no" ]; then
                echo "Cleanup is disabled.. Skipping cleanup for ${entry}"
              else
                echo "Rsync encountered an error. Skipping cleanup for ${entry}"
              fi
            else
              echo "Failed to create new dataset ${source_path}/${normalized_base_entry}"
            fi
          fi
        else
          echo "Skipping folder ${entry} due to insufficient space"
        fi
      fi
    fi
  done
}



#----------------------------------------------------------------------------------    
# this function prints what has been converted
#
print_new_datasets() {
 echo "The following folders were successfully converted to datasets:"
for folder in "${converted_folders[@]}"; do
  echo "$folder"
done
    }
    
#----------------------------------------------------------------------------------    
# this function checks if there any folders to covert in the array and if not exits. Also checks sources are valid locations
#
can_i_go_to_work() {
    echo "Checking if anything needs converting"
    
    # Check if the array is empty
    if [ ${#source_datasets_array[@]} -eq 0 ]; then
        echo "No sources are defined."
        echo "If you're expecting to process 'appdata' or VMs, ensure the respective variables are set to 'yes'."
        echo "For other datasets, please add their paths to 'source_datasets_array'."
        echo "No work for me to do. Exiting..."
        exit 1
    fi

    local folder_count=0
    local total_sources=${#source_datasets_array[@]}
    local sources_with_only_datasets=0
    
    for source_path in "${source_datasets_array[@]}"; do
        # Check if source exists
        if [[ ! -e "${mount_point}/${source_path}" ]]; then
            echo "Error: Source ${mount_point}/${source_path} does not exist. Please ensure the specified path is correct."
            exit 1
        fi
        
        # Check if source is a dataset
        if ! zfs list -o name | grep -q "^${source_path}$"; then
            echo "Error: Source ${source_path} is a folder. Sources must be a dataset to host child datasets. Please verify your configuration."
            exit 1
        else
            echo "Source ${source_path} is a dataset and valid for processing ..."
        fi
        
        local current_source_folder_count=0
        for entry in "${mount_point}/${source_path}"/*; do
            base_entry=$(basename "$entry")
            if [ -d "$entry" ] && ! zfs list -o name | grep -q "^${source_path}/$(echo "$base_entry")$"; then

                current_source_folder_count=$((current_source_folder_count + 1))
            fi
        done
        
        if [ "$current_source_folder_count" -eq 0 ]; then
            echo "All children in ${mount_point}/${source_path} are already datasets. No work to do for this source."
            sources_with_only_datasets=$((sources_with_only_datasets + 1))
        else
            echo "Folders found in ${source_path} that need converting..."
        fi
        
        folder_count=$((folder_count + current_source_folder_count))
    done

    if [ "$folder_count" -eq 0 ]; then
        echo "All children in all sources are already datasets. No work to do... Exiting"
        exit 1
    fi
}


#-------------------------------------------------------------------------------------
# this function runs through a loop sending all datasets to process the create_datasets
#
convert() {
for dataset in "${source_datasets_array[@]}"; do
  create_datasets "$dataset"
done
}

#--------------------------------
#    RUN THE FUNCTIONS          #
#--------------------------------
can_i_go_to_work
stop_docker_containers
stop_virtual_machines
convert
start_docker_containers
start_virtual_machines
print_new_datasets

