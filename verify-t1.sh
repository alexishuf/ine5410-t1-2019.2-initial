#!/bin/bash
# Usage: grade dir_or_archive [output]

# Ensure realpath 
realpath . &>/dev/null
HAD_REALPATH=$(test "$?" -eq 127 && echo no || echo yes)
if [ "$HAD_REALPATH" = "no" ]; then
  cat > /tmp/realpath-grade.c <<EOF
#include <stdlib.h>
#include <stdio.h>
#include <string.h>

int main(int argc, char** argv) {
  char* path = argv[1];
  char result[8192];
  memset(result, 0, 8192);

  if (argc == 1) {
      printf("Usage: %s path\n", argv[0]);
      return 2;
  }
  
  if (realpath(path, result)) {
    printf("%s\n", result);
    return 0;
  } else {
    printf("%s\n", argv[1]);
    return 1;
  }
}
EOF
  cc -o /tmp/realpath-grade /tmp/realpath-grade.c
  function realpath () {
    /tmp/realpath-grade $@
  }
fi

INFILE=$1
if [ -z "$INFILE" ]; then
  CWD_KBS=$(du -d 0 . | cut -f 1)
  if [ -n "$CWD_KBS" -a "$CWD_KBS" -gt 20000 ]; then
    echo "Chamado sem argumentos."\
         "Supus que \".\" deve ser avaliado, mas esse diretório é muito grande!"\
         "Se realmente deseja avaliar \".\", execute $0 ."
    exit 1
  fi
fi
test -z "$INFILE" && INFILE="."
INFILE=$(realpath "$INFILE")
# grades.csv is optional
OUTPUT=""
test -z "$2" || OUTPUT=$(realpath "$2")
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
# Absolute path to this script
THEPACK="${DIR}/$(basename "${BASH_SOURCE[0]}")"
STARTDIR=$(pwd)

# Split basename and extension
BASE=$(basename "$INFILE")
EXT=""
if [ ! -d "$INFILE" ]; then
  BASE=$(echo $(basename "$INFILE") | sed -E 's/^(.*)(\.(c|zip|(tar\.)?(gz|bz2|xz)))$/\1/g')
  EXT=$(echo  $(basename "$INFILE") | sed -E 's/^(.*)(\.(c|zip|(tar\.)?(gz|bz2|xz)))$/\2/g')
fi

# Setup working dir
rm -fr "/tmp/$BASE-test" || true
mkdir "/tmp/$BASE-test" || ( echo "Could not mkdir /tmp/$BASE-test"; exit 1 )
UNPACK_ROOT="/tmp/$BASE-test"
cd "$UNPACK_ROOT"

function cleanup () {
  test -n "$1" && echo "$1"
  cd "$STARTDIR"
  rm -fr "/tmp/$BASE-test"
  test "$HAD_REALPATH" = "yes" || rm /tmp/realpath-grade* &>/dev/null
  return 1 # helps with precedence
}

# Avoid messing up with the running user's home directory
# Not entirely safe, running as another user is recommended
export HOME=.

# Check if file is a tar archive
ISTAR=no
if [ ! -d "$INFILE" ]; then
  ISTAR=$( (tar tf "$INFILE" &> /dev/null && echo yes) || echo no )
fi

# Unpack the submission (or copy the dir)
if [ -d "$INFILE" ]; then
  cp -r "$INFILE" . || cleanup || exit 1 
elif [ "$EXT" = ".c" ]; then
  echo "Corrigindo um único arquivo .c. O recomendado é corrigir uma pasta ou  arquivo .tar.{gz,bz2,xz}, zip, como enviado ao moodle"
  mkdir c-files || cleanup || exit 1
  cp "$INFILE" c-files/ ||  cleanup || exit 1
elif [ "$EXT" = ".zip" ]; then
  unzip "$INFILE" || cleanup || exit 1
elif [ "$EXT" = ".tar.gz" ]; then
  tar zxf "$INFILE" || cleanup || exit 1
elif [ "$EXT" = ".tar.bz2" ]; then
  tar jxf "$INFILE" || cleanup || exit 1
elif [ "$EXT" = ".tar.xz" ]; then
  tar Jxf "$INFILE" || cleanup || exit 1
elif [ "$EXT" = ".gz" -a "$ISTAR" = "yes" ]; then
  tar zxf "$INFILE" || cleanup || exit 1
elif [ "$EXT" = ".gz" -a "$ISTAR" = "no" ]; then
  gzip -cdk "$INFILE" > "$BASE" || cleanup || exit 1
elif [ "$EXT" = ".bz2" -a "$ISTAR" = "yes"  ]; then
  tar jxf "$INFILE" || cleanup || exit 1
elif [ "$EXT" = ".bz2" -a "$ISTAR" = "no" ]; then
  bzip2 -cdk "$INFILE" > "$BASE" || cleanup || exit 1
elif [ "$EXT" = ".xz" -a "$ISTAR" = "yes"  ]; then
  tar Jxf "$INFILE" || cleanup || exit 1
elif [ "$EXT" = ".xz" -a "$ISTAR" = "no" ]; then
  xz -cdk "$INFILE" > "$BASE" || cleanup || exit 1
else
  echo "Unknown extension $EXT"; cleanup; exit 1
fi

# There must be exactly one top-level dir inside the submission
# As a fallback, if there is no directory, will work directly on 
# tmp/$BASE-test, but in this case there must be files! 
function get-legit-dirs  {
  find . -mindepth 1 -maxdepth 1 -type d | grep -vE '^\./__MACOS' | grep -vE '^\./\.'
}
NDIRS=$(get-legit-dirs | wc -l)
test "$NDIRS" -lt 2 || \
  cleanup "Malformed archive! Expected exactly one directory, found $NDIRS" || exit 1
test  "$NDIRS" -eq  1 -o  "$(find . -mindepth 1 -maxdepth 1 -type f | wc -l)" -gt 0  || \
  cleanup "Empty archive!" || exit 1
if [ "$NDIRS" -eq 1 ]; then #only cd if there is a dir
  cd "$(get-legit-dirs)"
fi

# Unpack the testbench
tail -n +$(($(grep -ahn  '^__TESTBENCH_MARKER__' "$THEPACK" | cut -f1 -d:) +1)) "$THEPACK" | tar zx
cd testbench || cleanup || exit 1

# Deploy additional binaries so that validate.sh can use them
test "$HAD_REALPATH" = "yes" || cp /tmp/realpath-grade "tools/realpath"
cc -std=c11 tools/wrap-function.c -o tools/wrap-function \
  || echo "Compilation of wrap-function.c failed. If you are on a Mac, brace for impact"
export PATH="$PATH:$(realpath "tools")"

# Run validate
(./validate.sh 2>&1 | tee validate.log) || cleanup || exit 1

# Write output file
if [ -n "$OUTPUT" ]; then
  #write grade
  echo "@@@###grade:" > result
  cat grade >> result || cleanup || exit 1
  #write feedback, falling back to validate.log
  echo "@@@###feedback:" >> result
  (test -f feedback && cat feedback >> result) || \
    (test -f validate.log && cat validate.log >> result) || \
    cleanup "No feedback file!" || exit 1
  #Copy result to output
  test ! -d "$OUTPUT" || cleanup "$OUTPUT is a directory!" || exit 1
  rm -f "$OUTPUT"
  cp result "$OUTPUT"
fi

if ( ! grep -E -- '-[0-9]+' grade &> /dev/null ); then
   echo -e "Grade for $BASE$EXT: $(cat grade)"
fi

cleanup || true

exit 0

__TESTBENCH_MARKER__
�      �<�v۶����@'!e�և?�J��J�S����M�ھ<�ټ�H��⤭f������b;3 H�KrR'���8>&	���` �(>���r��WK-H����lo����J�����F���v7�ڝ���=���XJ�,����{΄t�j�E��GS������h���?|���7I���
��9�y����[j��_�h��cm�s��n����߼��_=w��s'���}����x`?�?���ڵ�����vm�l�N8s=���6�5��1;aK�=k��m_r�d�}��%�j�1>����Ig�<?fc��
���6}�]�@�@Q=g*83�Ň!Ò�bʨ6[Jp�%l��h�{^�$��-DЪQ�T�Ww�-���ex+u��]1�۝�����ܸ��"=p��d6��(���峚���E>o4qϳy!��1��z1?�C��2����l�6�%f�K'���]����8M p�K !�<�8C�Z����9�~ʽXR�
ݘ�בE��G�!���z&�8��0�>>X�7e�L,d�{��21�T<6�7�s���È%v�8��:i�Am
+��,�X[�\�D� C�c-��|�z���!��98h�:��8��}-o�է�:>�����Mr��8��L�S>�xl>J�Y��"�W�UgYV�4�A	vu�%�	�3}�m���� ��Ӷm�ղ��R���v�(Q� �JP����/ـ�ଡ3��C��@՛p�$�,����_�gVҭiY'����H�m�]�<�m��̤%�gX|�|H5n��Ua��#�o�~��7?՝T�)'Q���$�aʌ����CK��V�"��ˑК�P?9��Y�<q���4���|j���"�,���.ޖ��HOO͓��vV�NO�ѤY��p����^ͷ1�j�La��I�n=�,+�~��;�,(�,R�\o�|E��g��1Sѧ��ו}ZϿ��儓�m���-��ե�1��\��;/	D��4����i)��IUw���
.0�:e�6�c�sɍ0���}������j�#Qy#��,�kU�;W�*�_�lRQj�nRS�|�8UyPO-��Iy6��ɐI*[br��R�*_�o� ������>T�Z�M8:��Ȏ���aӾgm��^��������`Q���1	5��`��/��/���^�w�8�=�?��k�������"��`A8�-�9� �}>�T�$���8�bI�{���/�8���D���d�m�c"�*Is�:B���l�Vd�d�p`���Ĉ�w�8 ������)�2d\a0K�%R��d� ���?�8dЊ1ˬ� ��{W?z����w�%�h�����w+����$�Ԝ��B���ďx�)X�h��-����Z��E�8��kM�"cןMF�+���f�%b�y��6h��VzL2��N~�=�5�\3=Ofѥ��9�!q@��r賑;�ʉH�1�Lc�A9���`͆hّ&(��П��泐�^4;O��ԉ��Xoej�J��5�,�*��ޝ�-:�ؐ�jB
ܐ5�!"E�f��:��ά���8b�[�~�|��?�0��c�sT�IY%�r\'H=��#�uR-#�3bH^	W۰���@�O�G=$�|z�8_����}�u$���q��v.aw�'�t�hg+���>`�3#?K�69K8@�9�Z�f� �<�t	�%�Q�Q��S5��N�O,b	M[d3[���Y�������]W7���e�.n(��7R�/�mLYY�W"�Th�gP��X�	�ɶ$����j� 4�|QE�ʅ�W)Av�SS|����(3�!��<kqu�����ޠ��)��:#޼r����Xp������!�n��$��������;��Nm���ᠷ�/������Z�y������Ͻ���kz�XR���w������Uo6��j7�����90�l��>0SXR��	Xew2
��[2��h�,pG=�l��*�zVh����Brʗ�� ���ɞ`�W�W�İ8�L�`�H)VKہ�-jG�emPܼ!I��X�+H#��-Qg�s�h�y�������OP�,�:${k�w� g�
@+9��|�G����',v���<t����+�MY�φ��ʊ!�R��/=�ͱ���Db7b\�>�g4(�Hd�Y�ѕ]�����V:�0_��`	�w.T�|Z	���x ky	��^>���ɤ���F
jJ��R"����#6�+�#�@C��t�|X/����~���.c5�h��^��S���ߜ�����QǢ������76�w�?�$����락�}�f@�?�Ɖ�N�F1=4�$p��#M�E�u��#�U��lø�h��Ɍ9�;�w�(i܀��qy*��\ڸ0R�b!�Mb����m����~�N�K�`�bghޥ��jɉ�����qe,}��/���.`����K��~����K�-���	g�4Ǭ͚�-��������8 �zIj4��M0 ��Q��Npy�4�r۲T%EN��uV�ZĀ�d�j22�]�*U���Л
�6ߒ ��t���S�;�9��@��O;������^+�����L@��_�1��!�2P�"TWg>���+ ;x�B4AS1z�%װT �^��
�`�ٳBsI0��l]uHb,�H�R.=-YCuJڤ�߄� �r��z�����d��Õ���h0��\]����=M�gbE�!�1t1�6(�b����A��¥�z3#L��| �VĚ}�8Z=]i�VW/[{�1�;�C�t���Lܑ�a3�[���:���������n����"=p�ވ��m�m�`ogp���?�w����:u�s �сNX���r���`#�<;>���̞)Im��k|X�d�a���'��P������0a�b��5G��&x��C�"ܔV�����M#>�JIzyPO��aLKcX�XQ�Wt���c�f^�^x`�RR�(~`�ȃ ��9���
�F�>؃�XTX��r����N�r��_�NI��#,0)��������&��Was;I W�I�ƣg��9nh���1�������p3t͌��пv�L�	W����j6�:��F�y�§I���<��l��f��-��Pu�n�k�80�F<�,D]$T���i,�+�С�aō�3�.�G�2���U��)��{#pV�&��z7��N�?������Za��޺���&i�4�D0,�/�����_' ��L�y3��l�ԉ/s���U42�\��c5�>Mj<���r�Xl_fܕ؟�C$�)҈G��M��;��0P�k0���k�!�a)���� ���ؐ���Y`EU�P�s9�}�j������Gv�͡DN�_Wb?��꜠������*D ��),�>��<1dA��EU�#K�ڵ])�,��7�J:7�(�J��S�Q���$�3�칍a>��Tt��m=vJ�I�v�(���=�g^�]���������*g�d
��x�P9Ƨ>8âA���aʃ���d[)�&�U�EqC�q��T('PƪQ�L�S	Y�$�I�7�TP�P�G�މ£�(��1@�B?�h��Ν[E1�i�B!6��T��Q�fRZ�S�a�[1JI6V~��ZY44�HEF�N��J=�$�ʭI��ן���2/�
�IඋP�A�%�o(���.�PI�\1�5h��9|�ZlK��u��2Y��6'�.sX]E�y!�a��!��g�":�O31�?R�˕+f5!a,�$YC�>e�= �����p-c� �AQʴ$�Pp�4>� �����2�[���G�!�e���k��	1��(*�"�Θ���|�-�[�r�G �"��:[��\��=�\�;��Y9c/���s�m���}��	����7W�y?sO=Co�{C+>�-ڐ�
��8������й� H%5թ�p��f����l���)/4᪊�j&h���'F#}t��30�X1�����@�hA�h�)+}�ԘRt�6�d[,�]m[	�(�}�:YIRH�.("Zm�%p2�:�s��Wl��*�[o	����al�S"�u�2�u-j���őtO+�V��7�/�B��@z��,���6�2���>�j_�a�]��^��w����k4ɢ��Yȷ��*B/ocǳ�u�%'��@ɚX�����K�3�<��3�%�JX>w'x�ciT��o���^[�X�����,�^�Q/E�D�-����a+_�23��b]�[;�\ҽ_�-9*���jH�����s�zFWykZr@����8�^��0j�#�����O;�/������q㾿�. ( �:���0�ю;�7ǈZ���s+x��.�S���s�WfH��������ĳ�=�YԔ$���3Td���#�N;�(��RŃ����rUz�U�(�A��K@�/�/���c�~>��L�T~�_ <��+e���#tu������<����j:�5���f�e�����Iru�?�����B,p�	)��!��OS�*�m͌puq�Y���j'vd�Ͼ���&�x��d��`��J����J��`�+�M�Z_y��֓[[�|����V����h��IRk+� tW�v[�x�����Mz ���Ɠz��G� �7��c�s]r��L�ѯ���
�֪,m�KN��V�:%��0�V��~���]i������|�H7)��r�R<���%'�aaO99q�d�P�*����nL<��i�ef胃�A�ԽZ�r��8Z�f6�ʈ�5���EUE��:�
�c��`O�	�Ps3s�ZvL��`9���ʝ�?l�'n����O����V�h'��Tҁp3��V���C����j���n���3M��߲���Y�|�%�ӷ[ W�V�=�Ym�W��;v�'���ܢ���,ܛ���O�dۆI�Z=w���֙~�]5L��Ct9={֮7%��w�
�לˁD0���*�}�o(.�V<J���L�:V���<t@M�.��Z����t*;�O<o���ݍ�n�������E*��K�����2 ���t-{x���8%�P��c�����;��u:�ةpP�9:�;!��G�K2�w��W �L�������O�����!�9��|�|�#��`�N)z��ةL�Y'�C4�]=�����ZN�`��w�0�H�,#(<ˣ!�.T���?���]�5���a���(����͑�H������|d{�BUI҉�X�.�F��D�2Q@�*U:ܕ��8�A8�qA�%�q�*�:w"Z
���K��z�L�sշL��Y��"	LRk&�3�)M�u�ΑP��\���$v�_$��N�. ���.c�{A�(��f�r�h�,�Ͳ��v��T�4�B_����#_��?�5}w;u,���k�B�g���������1��Y�F1�:�[�3t}�6���b�u"�7�aJ�����B��|��Z�����;���G�[�%���~y�=3����F�Ud2�l��W�/��ft:Ќ���Z- �6��{OE��̓����WP�˒q5%!����`FXǏ���O�\���� _?/�@/���#��K�Xl�}�b�)�;�K�6����h6��m{K�UB����(���T@9|��5'zG��5q�w<īz�|{�Cg�����j�9��1s���+��˺����g�o���/G������0�����/��}|���n��i�����a��{��z<~�4����������z���7�����He��W��^�w�*��z9E۳�jd�Ƥ�w���!ʡ����N�ga�]{0�ʋR/)[�Q❯U��9ȩ0tC���hޚ��qॡ�ږ̳�%$�QA�@d���� �a��C��[��o_�;�E}Um���q�����=�v�6��ç�'�\}�i���i]�I|�{mg۽�С%�f#�ZRR�$~��ڳ{���O��3�@�C��ns�s�X$8�`f�AR$ŧ�r=H�����$ךn�7��瞅�$l�8Ar�mt�+���:��g�#b�7R|9��1*lN	U�Si�w||����o긘��cZ(j�B0�5�U@�r�B�hء�`��Z�*�'��א`����߈�lex5B��b���ݽ��`:9b
*P5�C�X�B'.�iaq�Ь���NL>Gq�Sv�z�I'[Ce���\�a$�<G�5���'@E���DTD�|b����迲����g���������bxKV���b������m���9J���T܇.�*X\5��Cm+ċ�oz�_��8��Ft��U����+j�B�V�~"��cj?�E^Ű��Oq!�dD>��T��Z}��3�s}Q)'�"P+���P�����ҬTTB&Q�zQ�t/: Po��K��Ȁg��5���Tդ�7rφ�prɫ��T�̫h�Z�"RV7]9xMg}�Q��	��+��D0A����O��!�L����7ɭ���k��77^F{�Er&��N���ج}�Z��w�%KE�kh�(h_�d��o$^{��B�sP����b��䰤���>::�J~"���-C�,�w�d�����L��rWI��N~�Im�0�M�4�v�,�t~E���RjPg0$��4$���`�w���{O=;8�j[uW,�|�$;��4�:���Z'�~�LU,��B�J���ݹɍ"�t�{190�l֊��Rb����nKӸn��z�[+k�.;h�4�7"�}o�4�6��2�R� �����pH~�O�'/`�Fmr1N�r2eHd#��#�]��%�����҉��������/��$·���}1��I�!���H�(E2�<�����V�تg�Rb$�4�\M��%�4겫�S����<�lT��,�FB2Bէ^�̪�A~9w���Υؔ�J�k`3k���w*_��+���)�y�.p<�ɜ(��H�`5���1���G��_�V�,�7��D`���ȳ�BV-���GMH7��D��I'qE*�Σ�������_?U�"U�]-T{*-e��{��cP��V��4��4e�7�F�ts	�\��J�;!� ��i f��Yݘ�ڧ�;��t��h|�
���"NN�5ު$�J�*Ƽ}Mp,e1xA��­�hkc%E�m�mfU�N�Ǖ\�;�V0�8?,#��܋e��ylB��c��py%R�u��s]cϤ�D7Գ�۱��e�V�'J}�
_��"��"�Bm�*����`�%b��F�C.Z�U���)h+ϻ�J����l��M*s�H��.ݘog�D�;��fp����q��"bO�ә���|z�Z��^�V�54� F�l��&S )��{/�1ʨ�5�A7"�o�N����Ӟ�7־0�V�]Z�Ug�o釵|�~t@���rO��USn��	�l=g<L���]%`v����Oow�����o{��.�0� ����HFq�x�z���{#d��+�G!#Y�����x�?x�^�{b�"ݗ>[#��RJqyϒB���j���l=�i$���֥��N:�ޫ����D�4t�v�%��
'�rTW1�C����8�\�q`�?��fB���]��>!��q��6��� er�e!��@�q�H�}Z���N�Z�����&�>n&��<�6�'��}�0�l�/s_kL����*`Q�Z9� g�\��S���H� ��^GN��\e�u�Tb�:����'��b��Lfo
�u��p���o��Ֆ3�喹�\ ��X��)�Xi�sh����$w����-h�3�`n2����\k��8q��W̖��v^���uO�)P	˫������Lr�;�Gӟ�&E��g�x2�[��&ON��-�T)&
���%m��7jq�D_��Q=�DWP7�W��n��xl����O�FP_�k#L�~0�
��?��BSf�1x��P:^h�FO����&t=r�>�G�sr��r�T�L6�U���m��w�*�<_8S	3,�Gd�e|Ho��ɗAX�"��.�PUM�O���^V��hZ[3�p�+Q�����_zI�]��k��1������gq��l�X�1+��Z�y���P��T� ��:%	#L�`P�T�HE;��Ԩ�(� (���R|�0��u��(�Zy�	�D�ߪ�/�4a|���}w/�n4��c����lB�+'��p:.��,�e��Ju$�⧨R3k	'�y	�$�J����YFPڕj����^�7�ĻDb{�̂ʺ�)?H[��B6�jNi���!�Y�4??Oת���Y��Y�T�p��Y\�WJgZ�)`w��!�|��L�@<%�Ж�_�rc?X��-9#L.M�nƕ�m6SP7e����1��F��F��)>l�Zv�ǉCw�<~�2�(H,5�6ĸ�dX�$4mr�-��Wc�����e23'aK�ف��Bm�-"�!�%L��鵵]<��d�P�f�?o��HB�4o����_�z�zU�K6�؉��إzV��v��Jr�hKne��J��?�f%�\��5Y��S?�"xE~���`�-8��I�<��� 8��G�c{�4eg��3����q]�	`/�A�T�\�\Ehؒ�ka�j��kl�R^:+�7��J,}���$���������e���H��[�e�ʪ	�+q$�Jj��?����25�^doԼ��C�X��T��bZ�Z�Ɠ�EZ�v{3E�K�Z?٪N!��15�Z�}����Џ�L���^m[�ݮ'yJo�)NX*O�RH�r��'`fq믫BJ:�_��s�F}���\�St1Զ�6��m.�#���)��VV	�ʩʣ�?J����nL���HG�ɋ%��iUB:-<��K�e%�e�\F�"�SC,{�4�hf�1�0�։� ��4,_B?~S�������ٽ*�+JD ���P�Pe۷�DĖ�kM>����V�&�]˻�g+`��c�[�5�AȴNת'��i\��Bd�&c��k�	ns��?�����U�I��^�^->��V�8I�]rv��>��;�h��o�{x�r�4��\l��o�ܑ�a�9�hl0�e����Q����G����0��_(׵��杷r�%o���r`�S
��|���\sdn6�( A�rz���E�[%bdn�Q��0g� /�*���78��U�u�ļ7n0/� �,Jwݍ3�;�#���uV�
S[����,Pο��Y&�R�ƥ�[s�0A��X�0S��T)v�>�0��E\�96<�W��c"���Tx�|���S���pK"����M��$�B5w�)��������	X�>�^:�ܙ�)n_ �r��40m*��$�wdTe��'㝱$�T*^ܖ~)�j`�֒>�,/�K�l��*�l��L�W�Ͳ��{�-�ќ��	_-a�"J|,<��$˘�K@�����O ��#p����h8N���V!����&`~Lܦ'\��^�c>
���ʜ���B��F-��@�� �聪#7K�j��h*(����2���#�Te��"�*�{-��u{>G.�<�P����/U��a��a�Ț*�ޥ`5ֱ�)� ��
�p,� �%��j�H�9���r2E��~�H��b�˲�L"z��Ӈ�G�J0�
>'��.����vF[,�r�����6�ѿJ%���z�G����Dn�r�-p�"��5t0�7M'/Hx��yHM��UC�j���:�W�7�(g:3�U'C�da�,ᦣ����.���ԞQgINB���@~���E�EA55�G��4(P>D��\C�����ɯ?�!R�g�������Ҋ�B��0�xT��J&��r�#���y7�S�35��H�$�Y�V�<�.�Մ;6j�������������W��p�?]����9#���"��$��es3�T���GďzΡ[��=o���m�\
��ł�Y�*����aA���6��
�
8��� TXPr�y"�p�0 ���!�Pg�@��s�2�yG�弛� ��.�q�k�gG��������S�mM�����ߏ'��E�re���|���� �܂��r?F�|��e~훤�Q�����
$d�9ɉ�sa�F��^!vU�������S!!
����������G(0���x�5�w�_���@6��)��;M���㐝�cb�	�(�'>ɢp�G�B��èZ ۹;�P�~��m�yK�w8�T�ޔ���"rU��Q��fړ�U��3@�2�Ґ������	��!�3�sډj9�v�|�'"AM`I���?5��d��1m!&	�:wJ����pP�Aȉ�"�7���T|��`v_�8.�!ҎO�o��
�sE�h�����6���ڛ�Po���-�V,>��e]��}X_�2�?"�������쫴��]�,8e;U�<Ǣ�~�X���7��ʂ�������=X@if�$�z���BU�X��*��ʞ�rU����/�z�_z��B�(��w}�y�ߣ�>]��w�z��h��G�7 k5�+���Y�5~y���H'�g�^�YR@��3J���I��Fi�qC����>)V9��l�Va�&1�VYK�p�Ik����z��ɝ��	 :�Ɔ~,�����-������LJ�^��l76���ݢ���P�^�̂2c�t�G�e��D��������\�[RY�]��Yy���\Y2�E�5�:������>�b?�Ҭ������K(���dޕ������e�hJ�����K�X�g��ϗ���J)��W����W��c��h|�R�1�"��Jjm�z�]tF����0�n�;k��U�pɑ��We�kEVg�#OR�O�v�'�ơ]��fF�$��$��.m[���AU¬���9�'�Q��3�Y�>���E��7r���h

����П���_4�B��e=�&���-|�g� ��7w�u�5b�Eo���o�c�˜�krz��g��0u��ј��	!�NLB�~���(���t4P��S�:A�F��cTX�P�y��[
w��^4znb��9b(��KS/�Ř���c9*�yC2V�/�k�&���kV��˘J<���|cM�k��+�%�.�p+��,u���s�H��l�TA��>������Ek��N��x�6��XXQv!�4�?�p�Ɇ}���ｸW(����a�a<Y|%�C�{�����wŦ�#'��(^��_���(����r�o��ʾ�����pR^�����(�O�
3q�
\�3wؕ��thK��7�!�&O�K'��FW;�.��I'39�A-AY����:v<��r2el��2����e�O�@�pz6��E�pyn)�p��D�Q��W\?�n2�5s�zMf�y���C��[|�ق��ZG��N�_z��i���a6�~���|�8̮�cEGK��`�4zNg�?�4Ә�\��Ћo���o��$a;U���/U�����%��=w4gY0I�d�'�4ޥ�@�z̲ܬd��/��/-����q�������M�����-��+�3�9s�KGf�g^�2lI	�(W)>b�_��l�y�>aY��*1[�����_��N�^�n	o:���uެ3����s�턁w��V2�$ǡf[�BU�u��~�V髱�����q���3��=�a�]k��v�����؅* ����1v�|��C�d�
���Q����Q�����z�S�v$��?�O��i��б��;�>�İS?�����ґ�W�Gl�=b½h��F+:g�+�ug������uV�6�߳�7-�<�l5AP�MG#�%`q��p�Р�LƇ߶;	%��8:�>�8���Z]��7%g����Ux������u�/��,cB����Q�T�7|�ȷ�B�U����w�����F�}��a#@~�B�� y��gb��Lj��ŠUͼi21����u����S�&�q�2���d����K�+G���aY~����X.�����������ߧ����6��Ӄ�g'[rs��v{G�'���vz'���w�����i��X낵�Yk�
���;���Oͯ1��M�{y�p�pp�y���c:����� ���Gӑ���!��@��ѵE�`�+x9����t�����R{1j|�)�Oh�ͼ����{0���~����SJ_���ڄZ`j��e�x�Y�b^���Bx̂��m�I8
��M.�x�d�#�H B�sE\
e#l#��¤�N��炕���>��!�v]�:�|�xp�/X���Ί�G�ԡ-T}/A�BxP}��.�����9�|�s�u/'��f����wЊ�>�	 �#o����q3w��-w:	[�r��ϭo�E.���#1z/NQ�o�x��;������?tV�ڧ>d}w��H��puhF.�\�-�F�Go:�O�V�o Pߍ������ݽc��%t,� z:�h�̶��4@"QN#w��˩�\����[�7���w���-��ޒ%Ç��a��*'x���.(c
��~vx��D}�4@v�Qu�Z7�#cwO��	�X�6�C�_�PG�Ya�fhO���7�8M�A><"
��Ԕ�Z�/���/���:����q���=I4ja�G��,����g��b�K�`����O�#��j}g��Z{Э~��������A7���A{M�� ���{h��؃��÷?Ծ_�u:�ǵ�<j$�7>��D���e���K�m<��������G���^���<I��w'L�5D-d��-���a�$�@8���Ϩ���c�t<BW^���l�L��?<��jC̨5��0�i�`�������\�x�k������Z�]7z㏜�\�~��PAns���l4yM��J.���w�ȥ�u�J�Gp�� {�]�6�IXqE ��[�QI�M��d"\�B�`��QGp���̇���6p����������U�!����b��� ,�D�:�����kGRj����{z��N���z�qL�0b�O�
��a�3�&Bu\��T�]ZH04�H<�~���p�G�_�m�Q[�m�-�V�%�P|�;��2�#��a�o�lm�6"���o�:�6A&$�&�4�IȌ���u�1��d0�#��&JAո���3	O� sC�*m��)	ZZ��2N��������u��gB^m(�����?k�peE�#&���ģU!y;`�W��s|����o�� {?���u�� �a�"���wd>��`�Aľ���z���S�u������7��U�uo�F��Zoq�#Sc�ߋM�g�/���>>�n�4[���� ��ʠ��M���,y�����N�1o^�SP���e���*_�B��[ç�;�Ν,D��@�|e˪���E����NN��֔X���I���ί`���,�\�h÷��?;w��X��ҿ�kNAޮ~����W$��:�7���ġ��U�&���׉?c�އ9G��]��	�\"�\V�˔G.S�+~j�,�TwC���C�,��mE,eDq�ށ��͘Q����8���o�Ŷ�@�s���3V6�+�E����4�tZ��J`�A����D bdҢ�5$��&����f�Ν/I:��־C������̏aa�� oM�>�$�,U_d���4˩>��I̾��� "���:	l4YJ����Ɨ�q�f):Dxh�zg-�0x�K7�Ѻ|�c���#�c�p�c EBo�h���@��)P��x~X�.<@J���_&~�7-�!�\p�&�\�`���Yݛ�`0 ���O4	²����&�Z�e�T��lL7�+�l�l���\7n����:�L��T��Hc��h��>��A'�b�RM;��!S�58�1�6��1�pc7� ��D�T�RU�M^Ԑ���#�_1������eY�eY�eY�eY�eY�eY�eY�eY�eY�eY�eY�eY�eY�eY�eY�eY�eY�eY��v���֟Q @ 