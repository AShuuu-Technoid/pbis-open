/* Editor Settings: expandtabs and use 4 spaces for indentation
 * ex: set softtabstop=4 tabstop=8 expandtab shiftwidth=4: *
 * -*- mode: c, c-basic-offset: 4 -*- */

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

/*
 * Copyright (C) BeyondTrust Software. All rights reserved.
 *
 * Module Name:
 *
 *        nss-group.c
 *
 * Abstract:
 *
 *        Name Server Switch (BeyondTrust LSASS)
 *
 *        Handle NSS Group Information
 *
 * Authors: Krishna Ganugapati (krishnag@likewisesoftware.com)
 *          Sriram Nambakam (snambakam@likewisesoftware.com)
 *          Brian Koropoff (bkoropoff@likewisesoftware.com)
 *
 */

#include "lsanss.h"
#include "externs.h"
#include "nss-group.h"

typedef struct
{
    nss_backend_t base;
    LSA_ENUMGROUPS_STATE enumGroupsState;
    LSA_NSS_CACHED_HANDLE lsaConnection;
} LSA_NSS_GROUP_BACKEND, *PLSA_NSS_GROUP_BACKEND;

typedef NSS_STATUS (*NSS_ENTRYPOINT)(nss_backend_t*, void*);

#ifndef HAVE_STRUCT_NSS_XBYY_ARGS_RETURNLEN
/* In order to support NSS2 using a Sol 8 build
 * we need to define a NSS2 compatible nss_XbyY_args struct
 */
typedef struct nss_XbyY_nss2_args {
    nss_XbyY_buf_t  buf;
    int             stayopen;
#if defined(__STDC__)
    int             (*str2ent)      (const char             *instr,
                                    int                     instr_len,
                                    void *ent, char *buffer, int buflen);
#else
    int             (*str2ent)();
#endif
    union nss_XbyY_key key;
    void            *returnval;
    int             erange;
    int             h_errno;
    nss_status_t    status;
#if defined(__STDC__)
    int             (*key2str)  (void *buffer, size_t buflen,
                                void *key, size_t *len);
#else
    int             (*key2str)();
#endif
	size_t          returnlen;
} nss_XbyY_nss2_args_t;
#endif

static
NSS_STATUS
LsaNssSolarisGroupDestructor(
    nss_backend_t* pBackend,
    void* pArgs)
{
    PLSA_NSS_GROUP_BACKEND  pLsaBackend = (PLSA_NSS_GROUP_BACKEND) pBackend;
    PLSA_ENUMGROUPS_STATE   pEnumGroupsState = &pLsaBackend->enumGroupsState;
    int                     ret = NSS_STATUS_SUCCESS;

    LsaNssClearEnumGroupsState(
        &pLsaBackend->lsaConnection,
        pEnumGroupsState);
    LsaNssCommonCloseConnection(&pLsaBackend->lsaConnection);
    LsaFreeIgnoreHashes();
    LwFreeMemory(pBackend);

    return ret;
}

static
NSS_STATUS
LsaNssSolarisGroupSetgrent(
    nss_backend_t* pBackend,
    void* pArgs
    )
{
    NSS_STATUS status;
    PLSA_NSS_GROUP_BACKEND    pLsaBackend = (PLSA_NSS_GROUP_BACKEND) pBackend;
    PLSA_ENUMGROUPS_STATE     pEnumGroupsState = &pLsaBackend->enumGroupsState;

    NSS_LOCK();

    status = LsaNssCommonGroupSetgrent(
                                     &pLsaBackend->lsaConnection,
                                     pEnumGroupsState);
    NSS_UNLOCK();

    return status;
}

static
NSS_STATUS
LsaNssSolarisGroupGetgrent(
    nss_backend_t* pBackend,
    void* pArgs
    )
{
    PLSA_NSS_GROUP_BACKEND    pLsaBackend = (PLSA_NSS_GROUP_BACKEND) pBackend;
    PLSA_ENUMGROUPS_STATE     pEnumGroupsState = &pLsaBackend->enumGroupsState;
    nss_XbyY_args_t*          pXbyYArgs = (nss_XbyY_args_t*) pArgs;
    struct group*             pResultGroup = pXbyYArgs->buf.result;
    char *                    pszBuf = pXbyYArgs->buf.buffer;
    size_t                    bufLen = pXbyYArgs->buf.buflen;
    int                       err = 0;
    int*                      pErrorNumber = &err;
    int                       ret = NSS_STATUS_NOTFOUND;

    NSS_LOCK();

    ret = LsaNssCommonGroupGetgrent(
                                    &pLsaBackend->lsaConnection,
                                    pEnumGroupsState,
                                    pResultGroup,
                                    pszBuf,
                                    bufLen,
                                    pErrorNumber);

    NSS_UNLOCK();

    if (ret == NSS_STATUS_SUCCESS)
    {
        if (pResultGroup)
        {
            pXbyYArgs->returnval = pXbyYArgs->buf.result;
        }
        else
        {
            pXbyYArgs->returnval = pszBuf;
#ifdef HAVE_STRUCT_NSS_XBYY_ARGS_RETURNLEN
            pXbyYArgs->returnlen = strlen(pszBuf);
#else
            /* The pXbyYArgs->buf.result was NULL indicating this is NSS2/NSCD
             * Cast the nss_XbyY_args_t to a NSS2 compatible version.
             * NOTE: This is only required if we build on Solaris 8
             */
            ((nss_XbyY_nss2_args_t *)pXbyYArgs)->returnlen = strlen(pszBuf);
#endif
        }
    }
    else if (ret == NSS_STATUS_TRYAGAIN  && err == ERANGE)
    {
        pXbyYArgs->erange = 1;
        /* Solaris 8 will call again with the same buffer size if tryagain
         * is returned.
         */
        ret = NSS_STATUS_UNAVAIL;
    }
    else
    {
        errno = err;
    }

    return ret;
}

static
NSS_STATUS
LsaNssSolarisGroupEndgrent(
    nss_backend_t* pBackend,
    void* pArgs
    )
{
    NSS_STATUS status;
    PLSA_NSS_GROUP_BACKEND    pLsaBackend = (PLSA_NSS_GROUP_BACKEND) pBackend;
    PLSA_ENUMGROUPS_STATE     pEnumGroupsState = &pLsaBackend->enumGroupsState;

    NSS_LOCK();

    status = LsaNssCommonGroupEndgrent(
            &pLsaBackend->lsaConnection,
            pEnumGroupsState);

    NSS_UNLOCK();

    return status;
}

static
NSS_STATUS
LsaNssSolarisGroupGetgrgid(
    nss_backend_t* pBackend,
    void* pArgs
    )
{
    nss_XbyY_args_t*          pXbyYArgs = (nss_XbyY_args_t*) pArgs;
    gid_t                     gid = pXbyYArgs->key.gid;
    struct group*             pResultGroup = pXbyYArgs->buf.result;
    char*                     pszBuf = pXbyYArgs->buf.buffer;
    size_t                    bufLen = pXbyYArgs->buf.buflen;
    int                       err = 0;
    int*                      pErrorNumber = &err;
    int                       ret = NSS_STATUS_SUCCESS;
    PLSA_NSS_GROUP_BACKEND    pLsaBackend = (PLSA_NSS_GROUP_BACKEND) pBackend;

    NSS_LOCK();

    ret = LsaNssCommonGroupGetgrgid(
                                    &pLsaBackend->lsaConnection,
                                    gid,
                                    pResultGroup,
                                    pszBuf,
                                    bufLen,
                                    pErrorNumber);

    NSS_UNLOCK();

    if (ret == NSS_STATUS_SUCCESS)
    {
        if (pResultGroup)
        {
            pXbyYArgs->returnval = pXbyYArgs->buf.result;
        }
        else
        {
            pXbyYArgs->returnval = pszBuf;
#ifdef HAVE_STRUCT_NSS_XBYY_ARGS_RETURNLEN
            pXbyYArgs->returnlen = strlen(pszBuf);
#else
            /* The pXbyYArgs->buf.result was NULL indicating this is NSS2/NSCD
             * Cast the nss_XbyY_args_t to a NSS2 compatible version.
             * NOTE: This is only required if we build on Solaris 8
             */
            ((nss_XbyY_nss2_args_t *)pXbyYArgs)->returnlen = strlen(pszBuf);
#endif
        }
    }
    else if (ret == NSS_STATUS_TRYAGAIN  && err == ERANGE)
    {
        pXbyYArgs->erange = 1;
        /* Solaris 8 will call again with the same buffer size if tryagain
         * is returned.
         */
        ret = NSS_STATUS_UNAVAIL;
    }
    else if (ret == NSS_STATUS_UNAVAIL && err == ECONNREFUSED)
    {
        /* Librestart on Solaris does not like it when getpwnam_r returns
         * ECONNREFUSED. So instead, we'll treat this case like the user
         * was not found (0 for errno but NULL for result).
         */
        errno = 0;
    }
    else
    {
        errno = err;
    }

    return ret;
}

NSS_STATUS
LsaNssSolarisGroupGetgrnam(
    nss_backend_t* pBackend,
    void* pArgs
    )
{
    nss_XbyY_args_t*          pXbyYArgs = (nss_XbyY_args_t*) pArgs;
    const char *              pszGroupName = pXbyYArgs->key.name;
    struct group *            pResultGroup = (struct group*) pXbyYArgs->buf.result;
    char *                    pszBuf = pXbyYArgs->buf.buffer;
    size_t                    bufLen = pXbyYArgs->buf.buflen;
    int                       err = 0;
    int*                      pErrorNumber = &err;
    int                       ret = NSS_STATUS_SUCCESS;
    PLSA_NSS_GROUP_BACKEND    pLsaBackend = (PLSA_NSS_GROUP_BACKEND) pBackend;

    NSS_LOCK();

    ret = LsaNssCommonGroupGetgrnam(
                                    &pLsaBackend->lsaConnection,
                                    pszGroupName,
                                    pResultGroup,
                                    pszBuf,
                                    bufLen,
                                    pErrorNumber);

    NSS_UNLOCK();

    if (ret == NSS_STATUS_SUCCESS)
    {
        if (pResultGroup)
        {
            pXbyYArgs->returnval = pXbyYArgs->buf.result;
        }
        else
        {
            pXbyYArgs->returnval = pszBuf;
#ifdef HAVE_STRUCT_NSS_XBYY_ARGS_RETURNLEN
            pXbyYArgs->returnlen = strlen(pszBuf);
#else
            /* The pXbyYArgs->buf.result was NULL indicating this is NSS2/NSCD
             * Cast the nss_XbyY_args_t to a NSS2 compatible version.
             * NOTE: This is only required if we build on Solaris 8
             */
            ((nss_XbyY_nss2_args_t *)pXbyYArgs)->returnlen = strlen(pszBuf);
#endif
        }
    }
    else if (ret == NSS_STATUS_TRYAGAIN  && err == ERANGE)
    {
        pXbyYArgs->erange = 1;
        /* Solaris 8 will call again with the same buffer size if tryagain
         * is returned.
         */
        ret = NSS_STATUS_UNAVAIL;
    }
    else if (ret == NSS_STATUS_UNAVAIL && err == ECONNREFUSED)
    {
        /* Librestart on Solaris does not like it when getpwnam_r returns
         * ECONNREFUSED. So instead, we'll treat this case like the user
         * was not found (0 for errno but NULL for result).
         */
        errno = 0;
    }
    else
    {
        errno = err;
    }

    return ret;
}

NSS_STATUS
LsaNssSolarisGroupGetgroupsbymember(
    nss_backend_t* pBackend,
    void* pArgs
    )
{
    struct nss_groupsbymem* pGroupsByMem = (struct nss_groupsbymem*) pArgs;
    PCSTR                   pszUserName = pGroupsByMem->username;
    int*                    pResultsSize = &pGroupsByMem->numgids;
    int*                    pResultsCapacity = &pGroupsByMem->maxgids;
    gid_t*                  pGidResults = pGroupsByMem->gid_array;
    int                     err = 0;
    int*                    pErrorNumber = &err;
    int                     ret = NSS_STATUS_SUCCESS;
    PLSA_NSS_GROUP_BACKEND    pLsaBackend = (PLSA_NSS_GROUP_BACKEND) pBackend;

    size_t myResultsSize = *pResultsSize;
    size_t myResultsCapacity = *pResultsCapacity;

    NSS_LOCK();

    ret = LsaNssCommonGroupGetGroupsByUserName(
                &pLsaBackend->lsaConnection,
                pszUserName,
                myResultsSize,
                myResultsCapacity,
                &myResultsSize,
                pGidResults,
                pErrorNumber);

    NSS_UNLOCK();

    if (ret == NSS_STATUS_SUCCESS)
    {
        if (myResultsSize > myResultsCapacity)
            myResultsSize = myResultsCapacity;

        *pResultsSize = (int) myResultsSize;
    }

    return ret;
}

static
NSS_ENTRYPOINT
LsaNssSolarisGroupOps[] =
{
    LsaNssSolarisGroupDestructor,
    LsaNssSolarisGroupEndgrent,
    LsaNssSolarisGroupSetgrent,
    LsaNssSolarisGroupGetgrent,
    LsaNssSolarisGroupGetgrnam,
    LsaNssSolarisGroupGetgrgid,
    LsaNssSolarisGroupGetgroupsbymember
};

static
nss_backend_t
LsaNssSolarisGroupBackend =
{
    .n_ops = 7,
    .ops = LsaNssSolarisGroupOps
};

nss_backend_t*
LsaNssSolarisGroupCreateBackend(
    void
    )
{
    PLSA_NSS_GROUP_BACKEND pLsaBackend = NULL;

    if (LwAllocateMemory(sizeof(*pLsaBackend), (void**) &pLsaBackend))
    {
        return NULL;
    }

    pLsaBackend->base = LsaNssSolarisGroupBackend;

    return (nss_backend_t*) pLsaBackend;
}
