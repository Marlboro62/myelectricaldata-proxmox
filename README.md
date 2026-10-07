## ☕ Soutenir

Si ce script vous fait gagner du temps ou vous rend service, vous pouvez soutenir son développement :

[![Buy me a coffee](https://img.shields.io/badge/Buy%20me%20a%20coffee-d32f2f?logo=buymeacoffee&logoColor=white&style=flat)](https://buymeacoffee.com/marlboro62)
[![Ko-fi](https://img.shields.io/badge/Ko--fi-FF5E5B?logo=kofi&logoColor=white&style=flat)](https://ko-fi.com/nothing_one)

# MyElectricalData v2 — Script d'installation Proxmox (LXC)

Installe **MyElectricalData v2 en mode client** dans un conteneur LXC Proxmox, en **une seule commande**, sans Docker.

Le script crée le conteneur, installe PostgreSQL, le backend, l'interface web et le service, puis lance une première synchronisation de vos données Linky.

> Vous utilisez Home Assistant OS ? Préférez l'add-on : [Marlboro62/hassio-addons](https://github.com/Marlboro62/hassio-addons).

---

## ✅ Prérequis

- Un serveur **Proxmox VE 8 ou 9**
- Un compte sur **[www.v2.myelectricaldata.fr](https://www.v2.myelectricaldata.fr/)** avec le consentement Enedis effectué
- Vos identifiants API **`client_id`** et **`client_secret`**

### Où trouver mes identifiants API ?

1. Connectez-vous sur [www.v2.myelectricaldata.fr](https://www.v2.myelectricaldata.fr/)
2. Allez dans **Paramètres → API**
3. Copiez le **Client ID** (il commence par `cli_`) et le **Client Secret**

> ⚠️ Ne partagez jamais votre Client Secret (forum, capture d'écran, issue GitHub…).

---

## 🚀 Installation

Ouvrez le **shell du nœud Proxmox** (dans l'interface : cliquez sur le nom du nœud → **>_ Shell**), **pas** la console d'un conteneur.

Collez cette commande :

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/Marlboro62/myelectricaldata-proxmox/main/ct/myelectricaldata.sh)"
```

1. Le script vous demande d'abord votre **Client ID**, puis votre **Client Secret** : collez-les et validez avec **Entrée**
   - Le secret ne s'affiche pas pendant la saisie, c'est normal (comme un mot de passe)
   - Vous pouvez laisser vide et les ajouter plus tard (voir [Modifier les identifiants API](#modifier-les-identifiants-api))
2. Choisissez **Default Settings** (ou **Advanced** pour changer l'ID, le stockage, l'IP, la RAM…)
3. Patientez quelques minutes (la compilation de l'interface est l'étape la plus longue)

```
🌐  http://192.168.1.XXX:8100
```

### Installation sans questions (optionnel)

Vous pouvez fournir les identifiants directement dans la commande :

```bash
var_med_client_id="cli_xxxxxxxx" var_med_client_secret="xxxxxxxx" \
bash -c "$(curl -fsSL https://raw.githubusercontent.com/Marlboro62/myelectricaldata-proxmox/main/ct/myelectricaldata.sh)"
```

### Ressources par défaut

| Paramètre | Valeur |
| --- | --- |
| OS | Debian 13 |
| CPU | 2 cœurs |
| RAM | 2048 Mo |
| Disque | 8 Go |
| Type | Non privilégié |
| Port de l'interface | 8100 |

---

## ⚙️ Configuration après l'installation

### Première synchronisation

Au premier démarrage, une synchronisation se lance automatiquement (jusqu'à 3 ans d'historique). Elle peut prendre une à deux minutes. Ensuite, elle est faite **tous les jours à 6h00**.

Vous pouvez aussi la lancer à la main depuis le **Tableau de bord → Synchroniser**.

### Modifier les identifiants API

Si vous avez laissé les identifiants vides, ou si vous les avez régénérés :

```bash
# Depuis le shell du nœud Proxmox (remplacez 120 par l'ID de votre conteneur)
pct enter 120

# Dans le conteneur
nano /opt/myelectricaldata/.env
```

Modifiez ces deux lignes :

```
MED_CLIENT_ID=cli_xxxxxxxx
MED_CLIENT_SECRET=xxxxxxxx
```

Enregistrez (**Ctrl+O**, **Entrée**, **Ctrl+X**) puis redémarrez :

```bash
systemctl restart myelectricaldata
```

### Autres réglages du fichier `.env`

| Variable | Rôle |
| --- | --- |
| `MED_CLIENT_ID` / `MED_CLIENT_SECRET` | Vos identifiants API MyElectricalData |
| `VICTORIAMETRICS_URL` | URL de VictoriaMetrics si vous l'utilisez (optionnel) |
| `TZ` | Fuseau horaire (`Europe/Paris` par défaut) |
| `DATABASE_URL` / `SECRET_KEY` | Générés automatiquement, **ne pas modifier** |

### Home Assistant, MQTT, VictoriaMetrics

Les exports se configurent directement dans l'interface web, menus **Home Assistant**, **MQTT** et **VictoriaMetrics**.

---

## 🔄 Mise à jour

Dans la console du conteneur, tapez simplement :

```bash
update
```

Le script vérifie la dernière version de MyElectricalData, la télécharge, conserve votre `.env`, applique les migrations de la base et redémarre le service.

---

## 🛠️ Commandes utiles

Toutes ces commandes se lancent **dans le conteneur**.

```bash
# État du service
systemctl status myelectricaldata

# Logs en direct (Ctrl+C pour quitter)
journalctl -u myelectricaldata -f

# Redémarrer
systemctl restart myelectricaldata

# Vérifier que l'API répond
curl -s http://127.0.0.1:8100/api/ping
```

### Sauvegarde de la base

```bash
su - postgres -c "pg_dump myelectricaldata_client" > /root/myelectricaldata-backup.sql
```

Les sauvegardes Proxmox (vzdump) du conteneur fonctionnent aussi très bien.

---

## ❓ Dépannage

| Problème | Solution |
| --- | --- |
| `No MyElectricalData Installation Found!` | Vous avez lancé la commande dans un conteneur : utilisez le **shell du nœud** Proxmox |
| Page `502 Bad Gateway` | Le backend ne tourne pas : regardez `journalctl -u myelectricaldata -n 50` |
| Aucune donnée après la synchro | Vérifiez vos identifiants dans `.env` et le consentement Enedis sur le site |
| `curl: (22) ... 404` | Vérifiez que la commande est copiée en entier, sans espace en trop |

Un problème non listé ? Ouvrez une [issue](https://github.com/Marlboro62/myelectricaldata-proxmox/issues) avec la sortie de `journalctl -u myelectricaldata -n 50 --no-pager` (**en masquant vos identifiants**).

---

## 🗑️ Désinstallation

Depuis le shell du nœud Proxmox :

```bash
pct stop 120 && pct destroy 120
```

---

## 🙏 Crédits

- **[MyElectricalData](https://github.com/MyElectricalData/myelectricaldata_new)** : le projet et la passerelle Enedis
- **[community-scripts](https://github.com/community-scripts)** : le moteur de création des conteneurs LXC (Proxmox VE Helper-Scripts)

Ce script n'est **pas** un script officiel community-scripts : il utilise leur moteur, mais il est maintenu ici.

## 📜 Licence

MIT
