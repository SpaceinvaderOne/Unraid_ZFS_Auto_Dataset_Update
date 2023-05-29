#!/bin/bash
#set -x
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 
# #   Script for watching a dataset and auto updating regular folders converting them to datasets                                         # #
# #   (needs Unraid 6.12 or above)                                                                                                        # # 
# #   by - SpaceInvaderOne                                                                                                                # # 
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 


# real run or dry run
dry_run="yes"              # Set to "yes" for a dry run. Change to "no" to run for real

#
# Main Variables
source_pool="cyberflux"   #this is the zpool in which your source dataset resides (note the does NOT start with /mnt/)
source_dataset="appdata"  #this is the name of the dataset you want to check and convert its child directories to datasets
should_stop_containers="yes" # Setting to "yes" will stop all containers except thos listed below. This should be set to yes if watching the appdata share
containers_to_keep_running=("container1" "container2") #Containers that you do not want to be stopped (see readme)
should_stop_vms="yes"    #Setting to "yes" will stop all vms except thos listed below. This should be set to yes if watching the domain share
vms_to_keep_running=("vm1" "vm2") #Containers that you do not want to be stopped (see readme)
cleanup="yes"            #Seeting to yes will cleanup after running (see readme)

#
#Avanced variables you do not need to change these.
source_path="${source_pool}/${source_dataset}"
mount_point="/mnt"  
stopped_containers=()
stopped_vms=()

#
# This function is to stop running Docker containers if required
stop_docker_containers() {
  if [ "$should_stop_containers" = "yes" ]; then
    echo "Checking Docker containers..."
    for container in $(docker ps -q); do
      container_name=$(docker container inspect --format '{{.Name}}' $container | cut -c 2-)
      if ! [[ " ${containers_to_keep_running[@]} " =~ " ${container_name} " ]]; then
        echo "Stopping Docker container ${container_name}..."
        if [ "$dry_run" != "yes" ]; then
          docker stop $container
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
      echo "Restarting Docker container $(docker container inspect --format '{{.Name}}' $container)..."
      if [ "$dry_run" != "yes" ]; then
        docker start $container
      else
        echo "Dry Run: Docker container $(docker container inspect --format '{{.Name}}' $container) would be restarted"
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
  for entry in ${mount_point}/${source_path}/*; do
    if [ -d "$entry" ]; then
      base_entry=$(basename "$entry")
      if [[ "$base_entry" != *_temp ]]; then
        if ! zfs list | grep -q "${source_path}/${base_entry}"; then
          echo "Processing folder ${entry}..."
          folder_size=$(du -sb "$entry" | cut -f1)  # This is in bytes
          folder_size_hr=$(du -sh "$entry" | cut -f1)  # This is in human readale
          echo "Folder size: $folder_size_hr"
          if zfs list | grep -q "$source_path" && (( $(zfs list -o avail -p -H "${source_path}") >= folder_size )); then
            echo "Creating and populating new dataset ${source_path}/${base_entry}..."
            if [ "$dry_run" != "yes" ]; then
              cp -a "$entry" "${mount_point}/${source_path}/${base_entry}_temp"
              if zfs create "${source_path}/${base_entry}"; then
                rsync -a "${mount_point}/${source_path}/${base_entry}_temp/" "${mount_point}/${source_path}/${base_entry}/"
                if [ "$cleanup" = "yes" ]; then
                  rm -r "${mount_point}/${source_path}/${base_entry}_temp"
                fi
              else
                echo "Failed to create new dataset ${source_path}/${base_entry}"
              fi
            fi
          else
            echo "Skipping folder ${entry} due to insufficient space"
          fi
        fi
      fi
    fi
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

