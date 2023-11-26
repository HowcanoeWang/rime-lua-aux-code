file = './ZRM_Aux-code_4.3.txt'
out_file = './zrm_no_dup.txt'

no_dup = ''

with open(file, 'r') as f:

    for line in f.readlines():

        aux_code = line.split('=')[-1].split('\n')[0]

        if len(aux_code) == 2:
            no_dup += line

with open(out_file, 'w') as o:
    o.writelines(no_dup)