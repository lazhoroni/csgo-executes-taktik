# csgo-executes-taktik

- Hiç bir kaynakta taktik sunucusu için toplu bir paket görmedim. Sizlere taktik sunucusu için gerekli eklentileri birleştiriyorum.

- WASP sunucuları 0fir Executes eklentisini kullanmaktadır.

# Yapılacaklar:

- Spawnlar eklenecek.
- Türkçe rehberler eklenecek.

# 0fir Executes:

- databases.cfg

```
"executes"
{
        "driver"            "sqlite"
        "host"                "localhost"
        "database"            "executes-sqlite"
        "user"                "root"
        "pass"                ""
}
```

- Admin Commands:

sm_scramble - Scramble the teams in the next round.
sm_start - Skip the map load time.
sm_pistols - Toggle pistol only mode.

- To add/edit executes:

First type !edit to enable edit mode, to add spawns for the ct's stand wherever you want the ct's will be spawned and type !addct, to delete the closest ct spawn to you type !delct. To add execute type !add, a menu will pop up and you will need to set name for the execute by typing "!name <the execute name>" and then you will need to set a site for the execute by typing "!site <a or b>". After you finish setup the name and the site you will need to setup T spawns and Smokes, to add T spawns you will need to stand wherever you want the T will be spawned and press "Add T Spawn", you can delete T spawn by getting close to the spawn you want to delete and press "Delete T Spawn". After you finish T spawns you want to setup the smokes, you basically pressing "Add Smoke" then you throw a smoke you want to be included at the execute and later a menu will pop up with 3 options, "Throw Again" which will show you the smoke you just threw, "Confirm Smoke" that will add the smoke to the execute and "Cancel" which cancel the smoke and will let you try again. You can edit an execute by typing !execs and choosing the execute you want to edit.

# Splewis Executes:

- Creating Executes and Spawns

No default spawns or executes are provided. You must launch the editor and add them yourself. It's kind of hard to work with, so feel free to submit a pull request to make it better.

- Admin Commands:

!edit: launches the editor, opens the edit menu. You will use this a lot !setname: sets the name of the spawn/execute being edited !clearbuffers: clears any spawn/execute edit buffers
