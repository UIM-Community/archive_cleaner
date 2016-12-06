# archive_cleaner
CA UIM Archives cleaner

> Warning this probe only work on hub, the probe do local checkup with nimRequest only (dont use to do remote checkup).

The probe use Perluim framework. You can find it [Here](https://github.com/fraxken/perluim)

# Cfg setup 

> Do not use login and password when you package the script as probe 

```xml
<setup>
    login = 
    password = 
    domain = DOMAIN
    audit = 0
    output_directory = output
    output_cache = 3
    original_hub = YOURHUB
    update_rules = 0
</setup>
<CMDB>
   sql_host = 
   sql_user = 
   sql_password = 
   sql_database = 
</CMDB>
```
