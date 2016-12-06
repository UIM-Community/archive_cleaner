# archive_cleaner
CA UIM Archives cleaner. This perl script/probe delete all hubs package if their are not in the primary hub (set original_hub key in setup cfg section). Comparaison is done to name/version/build.

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
</setup>
```
