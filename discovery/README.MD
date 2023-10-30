# discovery desc

## discovery rule 
- #数据格式：sysObjectId,sysDescrPattern,_OBJ_CATEGORY,_OBJ_TYPE,VENDOR,MODEL

## import discovery dict
- ./dislibtool --action savetodb
- action默认为savetodb

## export discovery dict 
- ./dislibtool --action exportfile --savepath /tmp/dict
- savepath默认为当前路径
