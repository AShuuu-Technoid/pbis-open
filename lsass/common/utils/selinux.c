/*
 * Copyright © BeyondTrust Software 2004 - 2019
 * All rights reserved.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *        http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 *
 * BEYONDTRUST MAKES THIS SOFTWARE AVAILABLE UNDER OTHER LICENSING TERMS AS
 * WELL. IF YOU HAVE ENTERED INTO A SEPARATE LICENSE AGREEMENT WITH
 * BEYONDTRUST, THEN YOU MAY ELECT TO USE THE SOFTWARE UNDER THE TERMS OF THAT
 * SOFTWARE LICENSE AGREEMENT INSTEAD OF THE TERMS OF THE APACHE LICENSE,
 * NOTWITHSTANDING THE ABOVE NOTICE.  IF YOU HAVE QUESTIONS, OR WISH TO REQUEST
 * A COPY OF THE ALTERNATE LICENSING TERMS OFFERED BY BEYONDTRUST, PLEASE CONTACT
 * BEYONDTRUST AT beyondtrust.com/contact
 */

#include "includes.h"

typedef char* security_context_t;
typedef struct __SELINUX
{
    void *dlhandle;
    int (*is_selinux_enabled)();
    int (*matchpathcon_init)(const char *path);
    void (*matchpathcon_fini)(void);
    int (*matchpathcon)(const char *path, mode_t mode, security_context_t *con);
    int (*setfilecon)(const char *path, security_context_t con);
    void (*freecon)(security_context_t con);

    BOOLEAN bEnabled;
} SELINUX;

DWORD
SELinuxCreate(
    PSELINUX *ppSELinux
    )
{
    DWORD dwError = 0;
    PSELINUX pSELinux = NULL;
 
    dwError = LwAllocateMemory(sizeof(SELINUX), (PVOID*)&pSELinux);
    BAIL_ON_LSA_ERROR(dwError);

    pSELinux->bEnabled = FALSE;

#if ENABLE_SELINUX
    BOOLEAN bFileExists = FALSE;

    dwError = LsaCheckFileExists(LIBSELINUX, &bFileExists);
    BAIL_ON_LSA_ERROR(dwError);

    if (bFileExists == FALSE)
    {
        LSA_LOG_DEBUG("Could not find %s", LIBSELINUX);
        goto error;
    }

    pSELinux->dlhandle = dlopen(LIBSELINUX, RTLD_LAZY | RTLD_LOCAL);
    if (pSELinux->dlhandle == NULL)
    {
        LSA_LOG_ERROR("Could not load " LIBSELINUX ": %s", dlerror());
        goto cleanup;
    }
    else
    {
        pSELinux->is_selinux_enabled = dlsym(pSELinux->dlhandle, "is_selinux_enabled");
        pSELinux->matchpathcon_init = dlsym(pSELinux->dlhandle, "matchpathcon_init");
        pSELinux->matchpathcon_fini = dlsym(pSELinux->dlhandle, "matchpathcon_fini");
        pSELinux->matchpathcon = dlsym(pSELinux->dlhandle, "matchpathcon");
        pSELinux->setfilecon= dlsym(pSELinux->dlhandle, "setfilecon");
        pSELinux->freecon = dlsym(pSELinux->dlhandle, "freecon");
        if (!pSELinux->is_selinux_enabled ||
            !pSELinux->matchpathcon ||
            !pSELinux->setfilecon ||
            !pSELinux->freecon)
        {
            LSA_LOG_ERROR("Could not find symbol in " LIBSELINUX);
            dwError = LW_ERROR_LOOKUP_SYMBOL_FAILED;
            BAIL_ON_LSA_ERROR(dwError);
        }

        if (pSELinux->is_selinux_enabled() == 1)
        {
            LSA_LOG_DEBUG("SELinux is enabled.");
            if(pSELinux->matchpathcon_init != NULL)
            {
                pSELinux->matchpathcon_init(NULL);
            }            
            pSELinux->bEnabled = TRUE;
        }
    }
#endif
    *ppSELinux = pSELinux;

cleanup:
    return dwError;

error:
    LW_SAFE_FREE_MEMORY(pSELinux);
    goto cleanup;
}

DWORD
SELinuxSetContext(
    PCSTR pszPath,
    mode_t mode,
    PSELINUX pSELinux
    )
{
    DWORD dwError = 0;

#if ENABLE_SELINUX
    security_context_t context;

    if ((pSELinux && pSELinux->bEnabled))
    {
        if (pSELinux->matchpathcon(pszPath, mode, &context))
        {
            dwError = LW_ERROR_INTERNAL;
            BAIL_ON_LSA_ERROR(dwError);
        }
        else
        {
            if (pSELinux->setfilecon(pszPath, context) == -1)
            {
               dwError = LwMapErrnoToLwError(errno);
            }
            pSELinux->freecon(context);
            BAIL_ON_LSA_ERROR(dwError);
        }
    }

cleanup:
    return dwError;

error:
    goto cleanup;
#else
    return dwError;
#endif
}


VOID
SELinuxFree(
    PSELINUX pSELinux
    )
{
    if (pSELinux)
    {
#if ENABLE_SELINUX
        if (pSELinux->bEnabled)
        {
            if(pSELinux->matchpathcon_fini != NULL)
            {
                pSELinux->matchpathcon_fini();
            }            
        }
        if (pSELinux->dlhandle)
            dlclose(pSELinux->dlhandle);
#endif
        LW_SAFE_FREE_MEMORY(pSELinux);
    }
}

DWORD
LsaSELinuxManageHomeDir(
    PCSTR pszHomeDir
    )
{
    DWORD dwError = 0;
    PCSTR pszSemanageFormat = "semanage fcontext -a -e /home %s";
    PSTR pszRootHomeDir = NULL;
    PSTR pszSemanageExecute = NULL;
    int systemresult = 0;

    dwError = LsaGetDirectoryFromPath(pszHomeDir, &pszRootHomeDir);
    BAIL_ON_LSA_ERROR(dwError);

    if (LW_IS_NULL_OR_EMPTY_STR(pszRootHomeDir))
    {
        dwError = LW_ERROR_INVALID_PREFIX_PATH;
        BAIL_ON_LSA_ERROR(dwError);
    }

    if (pszRootHomeDir[0] != '/')
    {
        dwError = LW_ERROR_INVALID_PREFIX_PATH;
        BAIL_ON_LSA_ERROR(dwError);
    }

    if (pszRootHomeDir[1] == '\0')
    {
        dwError = LW_ERROR_INVALID_PREFIX_PATH;
        BAIL_ON_LSA_ERROR(dwError);
    }

    dwError = LwAllocateStringPrintf(
                    &pszSemanageExecute,
                    pszSemanageFormat,
                    pszRootHomeDir);
    BAIL_ON_LSA_ERROR(dwError);

    systemresult = system(pszSemanageExecute);
    if (systemresult < 0)
    {
        dwError = LwMapErrnoToLwError(errno);
        BAIL_ON_LSA_ERROR(dwError);
    }

cleanup:
    LW_SAFE_FREE_STRING(pszRootHomeDir);
    LW_SAFE_FREE_STRING(pszSemanageExecute);

    return dwError;

error:
    goto cleanup;
}

