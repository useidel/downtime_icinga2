# downtime.icinga2
Shell script to set/remove a downtime to/from a server (and services) for Icinga2

Still early days ... but seems to do the job for basic stuff

The script is intended to be the target of (soft) links which either set or remove downtime(s). The names of the corresponding (soft) links should contain the string "on" and "off", respectively. Personally I use the these file names "downtime.on.sh" and "downtime.off.sh".

![screenshot](assets/images/downtime.icinga2.png)


Next on my list the handling of downtimes for children

