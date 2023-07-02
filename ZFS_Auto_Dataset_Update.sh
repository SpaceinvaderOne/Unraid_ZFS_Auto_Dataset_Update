#!/bin/bash
#set -x
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 
# #   Script for watching a dataset and auto updating regular folders converting them to datasets                                         # #
# #   (needs Unraid 6.12 or above)                                                                                                        # # 
# #   by - SpaceInvaderOne                                                                                                                # # 
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 


# real run or dry run
dry_run="no"              # Set to "yes" for a dry run. Change to "no" to run for real

#
# Main Variables
source_pool="cyberflux"    #this is the zpool in which your source dataset resides (note the does NOT start with /mnt/)
source_dataset="appdata"     #this is the name of the dataset you want to check and convert its child directories to datasets
should_stop_containers="yes" # Setting to "yes" will stop all containers except thos listed below. This should be set to yes if watching the appdata share
containers_to_keep_running=("Emby" "container2") #Containers that you do not want to be stopped (see readme)
should_stop_vms="no"        #Setting to "yes" will stop all vms except thos listed below. This should be set to yes if watching the domain share
vms_to_keep_running=("Home Assistant" "vm2") #Containers that you do not want to be stopped (see readme)
cleanup="yes"               #Seeting to yes will cleanup after running (see readme)
replace_spaces="no"         # Set this to "no" to keep spaces in the dataset names
#
#
#Avanced variables you do not need to change these.
source_path="${source_pool}/${source_dataset}"
mount_point="/mnt"  
stopped_containers=()
stopped_vms=()
converted_folders=()
buffer_zone=11 # this is a bufferzone for addional free space needed in the dataset set as a percentage value beween 1 and 100.
#                it should be set a little higher than what you have your minimum free space floor that is set in the Unraid gui for the zpool

#
# This function is to stop running Docker containers if required
stop_docker_containers() {
  if [ "$should_stop_containers" = "yes" ]; then
    echo "Checking Docker containers..."
    for container in $(docker ps -q); do
      container_name=$(docker container inspect --format '{{.Name}}' "$container" | cut -c 2-)
      if ! [[ " ${containers_to_keep_running[@]} " =~ " ${container_name} " ]]; then
        echo "Stopping Docker container ${container_name}..."
        if [ "$dry_run" != "yes" ]; then
          docker stop "$container"
          stopped_containers+=($container)  # Save the id of the stopped container
        else
          echo "Dry Run: Docker container ${container_name} would be stopped"
        fi
      fi
    done
  fi
}

#
# this function is to stoprunning VMs if required
stop_virtual_machines() {
  if [ "$should_stop_vms" = "yes" ]; then
    echo "Checking VMs..."
    # Get the list of running vms
    running_vms=$(virsh list --name | awk NF)
    oldIFS=$IFS
    IFS=$'\n'
    
    for vm in $running_vms; do
      # restore the IFS
      IFS=$oldIFS
      
      # Check if VM is in the array of VMs to keep running
      if ! [[ " ${vms_to_keep_running[@]} " =~ " ${vm} " ]]; then
        echo "Stopping VM $vm..."
        if [ "$dry_run" != "yes" ]; then
          # Shutdown the VM then wait for it to stop
          virsh shutdown "$vm"
          for i in {1..18}; do
            if virsh domstate "$vm" | grep -q 'shut off'; then
              break
            fi
            if ((i == 18)); then
              virsh destroy "$vm"
            fi
            sleep 5
          done
          stopped_vms+=("$vm")  # Save the name of the stopped VM
        else
          echo "Dry Run: VM $vm would be stopped"
        fi
      fi
      # cchange IFS back to handle newline only for the next loop iteration
      IFS=$'\n'
    done
    # restore the IFS
    IFS=$oldIFS
  fi
}

#
# Function to start  Docker containers which had been stopped earlier
start_docker_containers() {
  if [ "$should_stop_containers" = "yes" ]; then
    for container in ${stopped_containers[@]}; do
      echo "Restarting Docker container $(docker container inspect --format '{{.Name}}' "$container")..."
      if [ "$dry_run" != "yes" ]; then
        docker start "$container"
      else
        echo "Dry Run: Docker container $(docker container inspect --format '{{.Name}}' "$container") would be restarted"
      fi
    done
  fi
}


#
# function  starts VMs that had been stopped earlier
start_virtual_machines() {
  if [ "$should_stop_vms" = "yes" ]; then
    for vm in "${stopped_vms[@]}"; do
      echo "Restarting VM $vm..."
      if [ "$dry_run" != "yes" ]; then
        virsh start "$vm"
      else
        echo "Dry Run: VM $vm would be started"
      fi
    done
  fi
}

#
# main function creating/converting to datasets and copying data within
create_datasets() {
  for entry in "${mount_point}/${source_path}"/*; do
    base_entry=$(basename "$entry")
    if [[ "$base_entry" != *_temp ]]; then
      normalized_base_entry=$(if [ "$replace_spaces" = "yes" ]; then echo "$base_entry" | tr ' ' '_'; else echo "$base_entry"; fi)
      if zfs list -o name | grep -q "^${source_path}/${normalized_base_entry}$"; then
        echo "Skipping dataset ${entry}..."
      elif [ -d "$entry" ]; then
        echo "Processing folder ${entry}..."
        folder_size=$(du -sb "$entry" | cut -f1)  # This is in bytes
        folder_size_hr=$(du -sh "$entry" | cut -f1)  # This is in human readable
        echo "Folder size: $folder_size_hr"
        buffer_zone_size=$((folder_size * buffer_zone / 100))
        if zfs list | grep -q "$source_path" && (( $(zfs list -o avail -p -H "${source_path}") >= buffer_zone_size )); then
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

print_new_datasets() {
 echo "The following folders were successfully converted to datasets:"
for folder in "${converted_folders[@]}"; do
  echo "$folder"
done
    }
#
#
# Run the functions
stop_docker_containers
stop_virtual_machines
create_datasets
start_docker_containers
start_virtual_machines
print_new_datasets

