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
 *        provider-main.h
 *
 * Abstract:
 *
 *        BeyondTrust Security and Authentication Subsystem (LSASS)
 *
 *        Active Directory Authentication Provider
 *
 * Authors: Krishna Ganugapati (krishnag@likewisesoftware.com)
 *          Sriram Nambakam (snambakam@likewisesoftware.com)
 *          Wei Fu (wfu@likewisesoftware.com)
 *          Brian Dunstan (bdunstan@likewisesoftware.com)
 *          Kyle Stemen (kstemen@likewisesoftware.com)
 */

#ifndef __LSA_UM_P_H__
#define __LSA_UM_P_H__

struct _LSA_UM_STATE;
typedef struct _LSA_UM_STATE *LSA_UM_STATE_HANDLE, **PLSA_UM_STATE_HANDLE;

VOID
LsaUmpStateDestroy(
    IN OUT LSA_UM_STATE_HANDLE Handle
    );

DWORD
LsaUmpStateCreate(
    IN PLSA_AD_PROVIDER_STATE pProviderState,
    OUT PLSA_UM_STATE_HANDLE pHandle
    );

VOID
LsaUmpTriggerCheckUsersThread(
    IN LSA_UM_STATE_HANDLE Handle
    );

DWORD
LsaUmpAddUser(
    IN LSA_UM_STATE_HANDLE  Handle,
    IN uid_t                uUid,
    IN PCSTR                pszUserName,
    IN PCSTR                pszPassword,
    IN DWORD                dwEndTime
    );

DWORD
LsaUmpModifyUserPassword(
    IN LSA_UM_STATE_HANDLE Handle,
    IN uid_t               uUid,
    IN PCSTR               pszPassword
    );

DWORD
LsaUmpModifyUserMountedDirectory(
    IN LSA_UM_STATE_HANDLE Handle,
    IN uid_t               uUid,
    IN PCSTR               pszMountedDirectory
    );

DWORD
LsaUmpRemoveUser(
    IN LSA_UM_STATE_HANDLE Handle,
    IN uid_t               uUid
    );

#endif /* __LSA_UM_P_H__ */
