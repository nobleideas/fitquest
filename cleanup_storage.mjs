import { createClient } from '@supabase/supabase-js';

const supabase = createClient(
  'https://innhkmqtrdxpsggxutxw.supabase.co/rest/v1/',
  'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImlubmhrbXF0cmR4cHNnZ3h1dHh3Iiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc2MTMzNTQyOCwiZXhwIjoyMDc2OTExNDI4fQ.hWVFS8iY_lo-A0-mXnD_hFvAAy1E-l52erdEboz_zgM'
);

const files = [
  'exercise_00e5b5de-1555-4d3f-a8a9-4b5afb606504/form.mov',
  'exercise_07910f08-f463-47f2-bd7a-542de986ad29/form.mov',
  'exercise_0c0667e8-80ae-43c4-b3a0-5b4d445bd516/form.mov',
  'exercise_130ebf72-9fe0-4ab5-812a-b75f79dfc06a/form.mov',
  'exercise_16875a73-c5d6-45bd-8ca3-ffff07827d74/form.mov',
  'exercise_16f96490-a177-48a7-9d07-f3573604c95c/form.mov',
  'exercise_16f9e7b7-5c1c-4aa5-8c0f-b309da8f8b67/form.mov',
  'exercise_188264cb-9448-49e5-8eb9-b096230ea0a0/form.mov',
  'exercise_196683fa-404e-43c7-a2d5-f999086eb3bd/form.mov',
  'exercise_1b8a6edf-3f69-4152-9dc6-d500e5c8cfdc/form.mov',
  'exercise_1b92bf99-c022-4018-ab99-6523be8b79f7/form.mov',
  'exercise_1cae6c1c-7601-4872-a9f5-fb32271b6383/form.mov',
  'exercise_1ce49c89-7477-4daa-9bd2-006efab67116/form.mov',
  'exercise_23347cbe-b669-4110-bfaa-80243ce8d263/form.mov',
  'exercise_2490ef4d-c752-4572-9633-019a5caeaf6e/form.mov',
  'exercise_29759cba-da63-49a8-9870-2ddf05af1984/form.mov',
  'exercise_2f24abd5-c2c5-4aa9-91f2-4cd8cb9cde4f/form.mov',
  'exercise_32b87771-e53b-4526-b222-3bca75389494/form.mov',
  'exercise_37d48732-dca9-4e41-bf1b-0580c6ef6288/form.mov',
  'exercise_3ae8285c-7842-4445-8f89-b676fa2ec536/form.mov',
  'exercise_3c4b9f30-2db8-430a-beec-9b6969060b61/form.mov',
  'exercise_3d07ad32-e409-4603-80ca-8dea5bfd7f35/form.mov',
  'exercise_3ea26745-c6cd-4271-ac3c-dad27d0326ab/form.mov',
  'exercise_40ada4a5-8ed5-426e-b01a-32611fda020e/form.mov',
  'exercise_41312115-41ac-4e0a-bb89-fbd661716aef/form.mov',
  'exercise_43cbacdf-d6de-4aad-af69-41a02b996e52/form.mov',
  'exercise_478eaeed-697f-49c0-b50c-336976f048ff/form.mov',
  'exercise_4be58e82-e18c-4e23-ac2f-b9987a128ded/form.mov',
  'exercise_4c576827-9aff-450e-9a3d-0b763f98cfe0/form.mov',
  'exercise_4f24c053-63f8-4170-a353-d7ab49499a07/form.mov',
  'exercise_4fe74fa7-7f65-4197-bede-4c98089ffab9/form.mov',
  'exercise_51b6722e-e3af-464b-9476-f302ed4d3ddd/form.mov',
  'exercise_52e14702-46de-476e-aa2e-78355d81c9db/form.mov',
  'exercise_56c3920d-1efd-4c78-ba8c-24b23d36eac4/form.mov',
  'exercise_5bd429d5-f3b6-4fb5-b214-240fff9378ac/form.mov',
  'exercise_5fd332e6-dddb-47bb-a27d-1e8c430b23bc/form.mov',
  'exercise_6bd15e3e-f4fb-46ad-b8dd-022e53cd3f16/form.mov',
  'exercise_6dd334b9-2101-41ab-898c-b590af9aaa35/form.mov',
  'exercise_71839b60-2598-4fc2-9428-a467b55f4666/form.mov',
  'exercise_751b0ea6-4a7f-4254-8f6c-bc353eddabf4/form.mov',
  'exercise_76264125-a1e9-48a5-a471-adbee403c964/form.mov',
  'exercise_79a25598-a795-4724-84e8-a872356fa4e5/form.mov',
  'exercise_7fb1e0a8-b4c4-472a-af02-79cc78f23f0a/form.mov',
  'exercise_80ad2350-ba17-4fed-9f8b-48d15141e433/form.mov',
  'exercise_845f882c-861d-4b22-89f6-0904f8acf0fd/form.mov',
  'exercise_8ae67b2b-182e-49a2-acf5-01b8f5425c4d/form.mov',
  'exercise_8cae4e27-2a00-4faa-b356-8b972b4eb121/form.mov',
  'exercise_8d966868-2759-43f1-b536-cbe6072b0e2a/form.mov',
  'exercise_90b14296-4d09-4af8-ae91-41878e44a415/form.mov',
  'exercise_9106129c-0be9-4dd9-b5cf-1a4de79e38ab/form.mov',
  'exercise_9d287efc-0460-4b3f-8297-fd6218139622/form.mov',
  'exercise_9dd04dca-7ca8-4ff8-87a8-f17d948b085e/form.mov',
  'exercise_9e57ec68-ac7a-4c32-ae50-b15591d42cdc/form.mov',
  'exercise_a0fd9a1e-469f-4b1e-a304-af9ba3ef53c9/form.mov',
  'exercise_a121e24f-d496-40e5-bc88-d12fa166aebb/form.mov',
  'exercise_a8088ee0-9720-435e-a39d-3f71cc44a653/form.mov',
  'exercise_ad69778e-2901-497f-b644-e63ac872f7fe/form.mov',
  'exercise_b2fed227-af17-4409-9cab-607e935dc922/form.mov',
  'exercise_b85a8402-1a7d-45f4-9ee8-62892ff39061/form.mov',
  'exercise_c2841e9d-4402-485b-b0e5-ca681ca25f46/form.mov',
  'exercise_c53014af-fe54-44ef-b045-605133abd4ff/form.mov',
  'exercise_c8188674-f152-45b1-8c4c-c301e9046190/form.mov',
  'exercise_c879f525-9cfb-4214-9bfd-eff5bda85a48/form.mov',
  'exercise_cd3992b7-8885-428b-9fa8-6585c9c875b9/form.mov',
  'exercise_d2df04cf-11e6-4090-870b-18b0d315feba/form.mov',
  'exercise_d52fb2e7-1aff-4b37-a1fb-78cffbfac5c5/form.mov',
  'exercise_d8fa7a4d-4330-4e25-a4a1-1ecfdd3e838e/form.mov',
  'exercise_dac30861-c5d5-4234-8f1b-c64dd2ef38e0/form.mov',
  'exercise_db49ccb6-88b1-41e1-8a5d-5ed4762eb5cb/form.mov',
  'exercise_e7d972b9-7cba-4872-bfd0-f700e5216793/form.mov',
  'exercise_f092bb5c-9286-47fc-bd23-c1e37af37561/form.mov',
  'exercise_f9afc307-5daa-4ced-92dc-ac8183c99fce/form.mov',
  'exercise_f9f83fdd-3394-453a-aaf8-ac90b3b6e05f/form.mov',
  'exercise_fa154998-02e8-48dc-a844-87c299f5b59b/form.mov',
  'exercise_fcae581f-36d1-4738-bb2c-06ce387a4196/form.mov',
  'exercise_ff09e0e1-4141-4d4a-892a-3783e41e929f/form.mov',
];

console.log(`Attempting to delete ${files.length} .mov files...`);

const { data, error } = await supabase.storage
  .from('exercise_form_video')
  .remove(files);

if (error) {
  console.error('DELETE FAILED');
  console.error(error);
  process.exit(1);
}

console.log(`Delete request completed.`);
console.log(data);