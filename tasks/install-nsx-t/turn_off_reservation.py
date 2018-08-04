# To run:
# python turn_off_reservation.py --host 10.40.1.206 \
#                                --user administrator@vsphere.local \
#                                --password 'Admin!23' \
#                                --vm_list vm_name1,vm_name2

from pyVmomi import vim

from pyVim.connect import SmartConnectNoSSL, Disconnect

import argparse
import atexit
import getpass
import json
import sys

from tools import cli
from tools import tasks

import pdb


def get_args():
    parser = argparse.ArgumentParser(
        description='Arguments for talking to vCenter')

    parser.add_argument('-s', '--host',
                        required=True,
                        action='store',
                        help='vSpehre service to connect to')

    parser.add_argument('-o', '--port',
                        type=int,
                        default=443,
                        action='store',
                        help='Port to connect on')

    parser.add_argument('-u', '--user',
                        required=True,
                        action='store',
                        help='User name to use')

    parser.add_argument('-p', '--password',
                        required=True,
                        action='store',
                        help='Password to use')

    parser.add_argument('-v', '--vm_list',
                        required=True,
                        action='store',
                        help='Comma separated list of VM names')

    args = parser.parse_args()
    return args


class ResourceReservationManager(object):
    def __init__(self):
        self._init_vc_view()

    def _init_vc_view(self):
        args = get_args()
        si = SmartConnectNoSSL(host=args.host, user=args.user,
                               pwd=args.password, port=args.port)
        if not si:
            print("Could not connect to the specified host using specified "
                  "username and password")
            return -1
        self.si = si
        atexit.register(Disconnect, si)

        self.content = si.RetrieveContent()
        self.vm_names = []
        try:
            self.vm_names = [vm_name.strip() for vm_name
                             in args.vm_list.split(',') if vm_name]
        except Exception:
            print "Error parsing vm_list: %s" % args.vm_list

        objview = self.content.viewManager.CreateContainerView(
            self.content.rootFolder, [vim.VirtualMachine], True)
        self.vm_obj_list = objview.view
        objview.Destroy()

    def _get_vm_by_name(self, vm_name):
        for vm in self.vm_obj_list:
            if vm.name == vm_name:
                return vm
        print "No VM found for %s" % vm_name

    def _power_on_vm_if_off(self, vm):
        if format(vm.runtime.powerState) == "poweredOff":
            task = vm.PowerOnVM_Task()
            tasks.wait_for_tasks(self.si, [task])

    def turn_off_vm_memory_reservation(self, vm):
        # first check if memory reservation is >0
        try:
            if vm.resourceConfig.memoryAllocation.reservation == 0:
                print 'resource reservation already at 0, returning'
                return

            if vm.config.memoryReservationLockedToMax:
                print "turn off memoryReservationLockedToMax"
                new_config = vim.VirtualMachineConfigSpec(
                    memoryReservationLockedToMax=False)
                task = vm.ReconfigVM_Task(spec=new_config)
                tasks.wait_for_tasks(self.si, [task])

            new_allocation = vim.ResourceAllocationInfo(reservation=0)
            new_config = vim.VirtualMachineConfigSpec(
                memoryAllocation=new_allocation)
            task = vm.ReconfigVM_Task(spec=new_config)
            tasks.wait_for_tasks(self.si, [task])

            self._power_on_vm_if_off(vm)
        except Exception as e:
            print 'unable to turn off reservation due to error: %s' % e

    def process(self):
        for vm_name in self.vm_names:
            vm = self._get_vm_by_name(vm_name)
            if vm:
                print "Trying to turn off reservation for VM %s" % vm.name
                self.turn_off_vm_memory_reservation(vm)
                print ''

if __name__ == "__main__":
    man = ResourceReservationManager()
    man.process()
