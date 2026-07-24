#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <dirent.h>
#include <curl/curl.h>
#include <cjson/cJSON.h>

#define FONTREPOS "fontrepos"

char fonts[4096] = "";

size_t json_write(void *ptr, size_t size, size_t nmemb, void *stream)
{
    return fwrite(ptr, size, nmemb, (FILE *)stream);
}

int fetchrepo(char repo[])
{
    CURL *curl = curl_easy_init();
    if (curl == NULL)
        return 1;

    FILE *fp = fopen("temprepo.json", "wb");
    if (fp == NULL) {
        curl_easy_cleanup(curl);
        return 1;
    }

    curl_easy_setopt(curl, CURLOPT_URL, repo);
    curl_easy_setopt(curl, CURLOPT_WRITEFUNCTION, json_write);
    curl_easy_setopt(curl, CURLOPT_WRITEDATA, fp);

    if (curl_easy_perform(curl) != CURLE_OK) {
        fclose(fp);
        curl_easy_cleanup(curl);
        return 1;
    }

    fclose(fp);
    curl_easy_cleanup(curl);

    fp = fopen("temprepo.json", "rb");
    if (fp == NULL)
        return 1;

    fseek(fp, 0, SEEK_END);
    long size = ftell(fp);
    rewind(fp);

    char *buffer = malloc(size + 1);
    if (buffer == NULL) {
        fclose(fp);
        return 1;
    }

    fread(buffer, 1, size, fp);
    buffer[size] = '\0';
    fclose(fp);

    cJSON *root = cJSON_Parse(buffer);
    free(buffer);

    if (root == NULL)
        return 1;

    cJSON *repoName = cJSON_GetObjectItem(root, "repo_name");

    if (!cJSON_IsString(repoName)) {
        cJSON_Delete(root);
        return 1;
    }

    char filename[512];
    snprintf(filename, sizeof(filename),
             "%s/%s.json", FONTREPOS, repoName->valuestring);

    FILE *out = fopen(filename, "wb");
    if (out == NULL) {
        cJSON_Delete(root);
        return 1;
    }

    cJSON_PrintPreallocated(root, NULL, 0, 0);

    char *json = cJSON_Print(root);
    if (json != NULL) {
        fwrite(json, 1, strlen(json), out);
        free(json);
    }

    fclose(out);
    cJSON_Delete(root);

    remove("temprepo.json");

    return 0;
}

int readrepos(void)
{
    DIR *dir = opendir(FONTREPOS);
    if (dir == NULL)
        return 1;

    fonts[0] = '\0';

    struct dirent *entry;

    while ((entry = readdir(dir)) != NULL) {

        if (entry->d_name[0] == '.')
            continue;

        char path[512];
        snprintf(path, sizeof(path),
                 "%s/%s", FONTREPOS, entry->d_name);

        FILE *fp = fopen(path, "rb");
        if (fp == NULL)
            continue;

        fseek(fp, 0, SEEK_END);
        long size = ftell(fp);
        rewind(fp);

        char *buffer = malloc(size + 1);
        if (buffer == NULL) {
            fclose(fp);
            continue;
        }

        fread(buffer, 1, size, fp);
        buffer[size] = '\0';
        fclose(fp);

        cJSON *root = cJSON_Parse(buffer);
        free(buffer);

        if (root == NULL)
            continue;

        cJSON *fontsArray = cJSON_GetObjectItem(root, "fonts");

        if (cJSON_IsArray(fontsArray)) {

            int count = cJSON_GetArraySize(fontsArray);

            for (int i = 0; i < count; i++) {

                cJSON *font = cJSON_GetArrayItem(fontsArray, i);
                if (!cJSON_IsObject(font))
                    continue;

                cJSON *name = cJSON_GetObjectItem(font, "name");

                if (cJSON_IsString(name)) {

                    if (strlen(fonts) != 0)
                        strcat(fonts, ", ");

                    strcat(fonts, name->valuestring);
                }
            }
        }

        cJSON_Delete(root);
    }

    closedir(dir);

    return 0;
}

