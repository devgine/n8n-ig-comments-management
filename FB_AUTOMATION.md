# Workflow n8n Facebook — mise en place

Workflow : `facebook-comment-automation.json` (séparé du workflow Instagram).

## Ce qu'il fait
1. Webhook Page Facebook (champ `feed`) : ne garde que les **nouveaux commentaires** (`item=comment`, `verb=add`).
2. Ignore les commentaires de la Page elle-même, déduplique dans Postgres (`fb_processed_comments`).
3. Si le commentaire contient un mot-clé de **Message Rules Configuration** (ex. `abc`) :
   - **aime le commentaire** (`POST /{comment-id}/likes`, une erreur ne bloque pas la suite) ;
   - envoie un **DM privé avec bouton** vers le guide (`POST /{page-id}/messages`, `recipient.comment_id`) ;
   - puis une **réponse publique** sous le commentaire (`POST /{comment-id}/comments`).
4. Sans mot-clé : rien n'est envoyé.

Pas de vérification d'abonnement : Facebook ne l'expose pas (contrairement à Instagram).

## Prérequis
- Une **Page** Facebook (pas un profil perso), reliée à l'app Meta.
- Permissions : `pages_show_list`, `pages_manage_metadata`, `pages_read_engagement`, `pages_messaging`, `pages_manage_engagement`.
- Variables d'environnement n8n : `FACEBOOK_PAGE_ACCESS_TOKEN` (jeton de **Page**, longue durée), `FACEBOOK_PAGE_ID`, `FACEBOOK_VERIFY_TOKEN`.
- Webhook Meta : URL `https://<n8n>/webhook/facebook-comments`, abonnement de la Page au champ **feed**.
- Table Postgres : `fb_processed_comments.sql`.

## Limites Meta
- Une seule réponse privée par commentaire, dans les 7 jours.
- Texte du DM ≤ 640 caractères, titre de bouton court.
- En accès Standard, l'app ne traite que les personnes ayant un rôle sur l'app : pour le public, il faut l'Advanced Access (App Review).