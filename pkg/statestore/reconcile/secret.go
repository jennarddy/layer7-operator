/*
* Copyright (c) 2025 Broadcom. All rights reserved.
* The term "Broadcom" refers to Broadcom Inc. and/or its subsidiaries.
* All trademarks, trade names, service marks, and logos referenced
* herein belong to their respective companies.
*
* This software and all information contained therein is confidential
* and proprietary and shall not be duplicated, used, disclosed or
* disseminated in any way except as authorized by the applicable
* license agreement, without the express written permission of Broadcom.
* All authorized reproductions must be marked with this language.
*
* EXCEPT AS SET FORTH IN THE APPLICABLE LICENSE AGREEMENT, TO THE
* EXTENT PERMITTED BY APPLICABLE LAW OR AS AGREED BY BROADCOM IN ITS
* APPLICABLE LICENSE AGREEMENT, BROADCOM PROVIDES THIS DOCUMENTATION
* "AS IS" WITHOUT WARRANTY OF ANY KIND, INCLUDING WITHOUT LIMITATION,
* ANY IMPLIED WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR
* PURPOSE, OR. NONINFRINGEMENT. IN NO EVENT WILL BROADCOM BE LIABLE TO
* THE END USER OR ANY THIRD PARTY FOR ANY LOSS OR DAMAGE, DIRECT OR
* INDIRECT, FROM THE USE OF THIS DOCUMENTATION, INCLUDING WITHOUT LIMITATION,
* LOST PROFITS, LOST INVESTMENT, BUSINESS INTERRUPTION, GOODWILL, OR
* LOST DATA, EVEN IF BROADCOM IS EXPRESSLY ADVISED IN ADVANCE OF THE
* POSSIBILITY OF SUCH LOSS OR DAMAGE.
*
 */

package reconcile

import (
	"context"
	"encoding/json"
	"fmt"

	"github.com/caapim/layer7-operator/pkg/statestore"
	corev1 "k8s.io/api/core/v1"
	k8serrors "k8s.io/apimachinery/pkg/api/errors"
	"k8s.io/apimachinery/pkg/types"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/controller/controllerutil"
)

func Secret(ctx context.Context, params Params) error {
	// Currently scoped to Redis support

	desiredSecrets := []*corev1.Secret{}

	if params.Instance.Spec.Redis.ExistingSecret == "" {
		data := map[string][]byte{}
		data["username"] = []byte(params.Instance.Spec.Redis.Username)
		data["masterPassword"] = []byte(params.Instance.Spec.Redis.MasterPassword)
		desiredSecrets = append(desiredSecrets, statestore.NewSecret(params.Instance, data, params.Instance.Name+"-secret"))
	}

	data := map[string][]byte{}

	redisConf := params.Instance.Spec.Redis

	redisConf.Username = ""
	redisConf.MasterPassword = ""

	confBytes, err := json.Marshal(redisConf)
	if err != nil {
		return fmt.Errorf("failed to reconcile secrets: %w", err)
	}
	data["config.json"] = confBytes
	desiredSecrets = append(desiredSecrets, statestore.NewSecret(params.Instance, data, params.Instance.Name+"-config-secret"))

	if err := reconcileSecrets(ctx, params, desiredSecrets); err != nil {
		return fmt.Errorf("failed to reconcile secrets: %w", err)
	}
	return nil
}

func reconcileSecrets(ctx context.Context, params Params, desiredSecrets []*corev1.Secret) error {
	for _, ds := range desiredSecrets {
		desiredSecret := ds
		if err := controllerutil.SetControllerReference(params.Instance, desiredSecret, params.Scheme); err != nil {
			return fmt.Errorf("failed to set controller reference: %w", err)
		}

		currentSecret := corev1.Secret{}

		err := params.Client.Get(ctx, types.NamespacedName{Name: desiredSecret.Name, Namespace: params.Instance.Namespace}, &currentSecret)
		if err != nil && k8serrors.IsNotFound(err) {
			if err = params.Client.Create(ctx, desiredSecret); err != nil {
				return err
			}
			params.Log.Info("created secret", "name", desiredSecret.Name, "namespace", params.Instance.Namespace)
			continue
		}
		if err != nil {
			return err
		}

		if desiredSecret.ObjectMeta.Annotations["checksum/data"] != currentSecret.ObjectMeta.Annotations["checksum/data"] {
			patch := client.MergeFrom(&currentSecret)
			if err := params.Client.Patch(ctx, desiredSecret, patch); err != nil {
				return err
			}
			params.Log.V(2).Info("secret updated", "name", desiredSecret.Name, "namespace", desiredSecret.Namespace)
		}
	}

	return nil
}
